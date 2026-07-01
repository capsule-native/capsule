//
//  ContainerLifecycleModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Owns the
//  non-destructive lifecycle actions (start/stop/attach); ContainerBrowserModel stays a
//  pure read surface.

import CapsuleBackend
import Foundation
import Observation

@MainActor
@Observable
public final class ContainerLifecycleModel {
    public private(set) var busy: Set<String> = []
    public private(set) var attachSession: AttachSession?
    public var notice: LifecycleNotice?
    /// A pending destructive confirmation the UI should present, or nil.
    public var confirmation: ConfirmationRequest?

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void
    private let reloadList: @MainActor () async -> Void
    private let currentState: @MainActor (String) -> ContainerState
    private let terminalAvailable: @MainActor () -> Bool
    private let copyCommand: @MainActor ([String]) -> Void
    private let launchTerminal: @MainActor (TerminalRequest) -> Void
    private let openExternalTerminal: @MainActor ([String]) -> Void
    private let taskCenter: TaskCenter?
    private let settleAttempts: Int
    private let settleDelay: Duration
    private let hangTimeout: Duration

    private var attachTask: Task<Void, Never>?
    private var nextLogLineID = 0

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in },
        reloadList: @escaping @MainActor () async -> Void = {},
        currentState: @escaping @MainActor (String) -> ContainerState = { _ in .unknown },
        terminalAvailable: @escaping @MainActor () -> Bool = { false },
        copyCommand: @escaping @MainActor ([String]) -> Void = { _ in },
        launchTerminal: @escaping @MainActor (TerminalRequest) -> Void = { _ in },
        openExternalTerminal: @escaping @MainActor ([String]) -> Void = { _ in },
        taskCenter: TaskCenter? = nil,
        settleAttempts: Int = 4,
        settleDelay: Duration = .milliseconds(400),
        hangTimeout: Duration = .seconds(8)
    ) {
        self.backend = backend
        self.normalize = normalize
        self.onActivity = onActivity
        self.reloadList = reloadList
        self.currentState = currentState
        self.terminalAvailable = terminalAvailable
        self.copyCommand = copyCommand
        self.launchTerminal = launchTerminal
        self.openExternalTerminal = openExternalTerminal
        self.taskCenter = taskCenter
        self.settleAttempts = settleAttempts
        self.settleDelay = settleDelay
        self.hangTimeout = hangTimeout
    }

    /// Whether interactive affordances (Open Shell, real attach) are available yet.
    public var isTerminalAvailable: Bool { terminalAvailable() }

    /// Opens an interactive shell (`exec -it … sh`) in the embedded terminal, or copies the
    /// command to the clipboard when the terminal is unavailable.
    public func openShell(id: String) {
        launchOrCopy(
            TerminalRequest(
                containerID: id, title: "Shell · \(id)",
                argv: execInvocation(id: id, command: []).argv, kind: .execShell))
    }

    /// Runs a custom command interactively (`exec -it … <command>`) in the embedded terminal,
    /// falling back to the clipboard. An empty command defaults to `sh`.
    public func execShell(id: String, command: [String]) {
        launchOrCopy(
            TerminalRequest(
                containerID: id, title: "Exec · \(id)",
                argv: execInvocation(id: id, command: command).argv, kind: .execShell))
    }

    /// The faithful `exec -it <id> <command>` invocation (defaults to `sh`) — the single
    /// source of truth shared by the shell/exec actions and the Exec sheet's preview.
    public func execInvocation(id: String, command: [String]) -> CommandInvocation {
        CommandInvocation(CLICommand.execShell(id: id, command: command))
    }

    /// The `container prune` invocation, for the Clean Up sheet's preview.
    public var pruneInvocation: CommandInvocation {
        CommandInvocation(CLICommand.pruneContainers())
    }

    /// Starts a stopped container attached to its main process (`start -ai`) in the embedded
    /// terminal — the interactive counterpart to the read-only `logs --follow` attach.
    public func attachInteractively(id: String) {
        launchOrCopy(
            TerminalRequest(
                containerID: id, title: "Attach · \(id)",
                argv: ["container", "start", "-ai", id], kind: .interactiveAttach))
    }

    /// Runs an arbitrary recovery command in the embedded terminal (the real
    /// retry-in-terminal), falling back to the clipboard when the terminal is unavailable.
    public func runInTerminal(_ command: [String]) {
        launchOrCopy(
            TerminalRequest(
                containerID: nil, title: "Terminal", argv: command, kind: .retry))
    }

    /// Routes a request to the embedded terminal when available, else copies its command.
    private func launchOrCopy(_ request: TerminalRequest) {
        if terminalAvailable() {
            launchTerminal(request)
        } else {
            copyCommand(request.argv)
        }
    }

    /// Detach fallback: run the command in the external Terminal.app instead of the embedded
    /// terminal (e.g. to keep a long interactive session open outside Capsule).
    public func openInExternalTerminal(_ argv: [String]) {
        openExternalTerminal(argv)
    }

    // MARK: - Start

    public func start(id: String, attach: Bool) async -> ContainerStartResult {
        busy.insert(id)
        defer { busy.remove(id) }
        do {
            try await backend.startContainer(id: id)
        } catch {
            let capsule = normalize(error)
            switch capsule.status {
            case .backendUnavailable:
                onActivity("Start failed — container service unavailable.")
                notice = LifecycleNotice(detail: capsule.detail)
                return .backendUnavailable
            case .failedBeforeExecution:
                notice = LifecycleNotice(detail: capsule.detail)
                return .failedBeforeExecution
            default:
                // The container resource pre-exists for `start`, so a failure here is
                // "created but not started", not "run failed".
                onActivity("“\(id)” created but not started.")
                notice = LifecycleNotice(detail: capsule.detail)
                return .createdButNotStarted
            }
        }

        // Provisional success → verify over a bounded settle window (best-effort).
        var running = false
        for _ in 0..<max(1, settleAttempts) {
            await reloadList()
            if currentState(id) == .running {
                running = true
                break
            }
            if settleDelay > .zero { try? await Task.sleep(for: settleDelay) }
        }
        guard running else {
            onActivity("“\(id)” failed to run.")
            notice = LifecycleNotice(
                detail: CapsuleError.commandFailed(
                    command: ["container", "start", id], exitCode: nil,
                    stderr: "Container did not reach the running state."
                ).detail)
            return .runFailed
        }

        onActivity("Started “\(id)”.")
        if attach { beginAttach(id: id) }
        return .started(attached: attach)
    }

    /// Sequential, continue-on-failure bulk start; attach is disabled for multi-select.
    public func startAll(ids: [String]) async {
        var ok = 0
        for id in ids where currentState(id) != .running {
            if case .started = await start(id: id, attach: false) { ok += 1 }
        }
        onActivity("Started \(ok) of \(ids.count) container(s).")
    }

    // MARK: - Stop

    /// Gracefully stops a container, racing the call against a hang watchdog. On hang the
    /// original stop continues in the background (idempotent) while a notice offers the
    /// interim Force Stop. "Already stopped / not running" is benign — and is intercepted
    /// before normalization so it is never misread as a daemon outage.
    public func stop(id: String, options: StopOptions) async -> StopOutcome {
        busy.insert(id)
        defer { busy.remove(id) }

        // Run the stop in its own task so the watchdog can time out WITHOUT cancelling it.
        let stopTask = Task { () -> (any Error)? in
            do {
                try await self.backend.stopContainer(id: id, options: options)
                return nil
            } catch {
                return error
            }
        }

        let finishedInTime = await raceAgainstHangTimeout(stopTask)
        guard finishedInTime else {
            onActivity("Stopping “\(id)” is taking longer than expected.")
            notice = makeHangNotice(id: id)
            return .hung
        }

        if let error = await stopTask.value {
            if isBenignAlreadyStopped(error) {
                onActivity("“\(id)” was already stopped.")
                return .alreadyStopped
            }
            let detail = normalize(error).detail
            notice = LifecycleNotice(detail: detail)
            return .failed(detail)
        }

        await reloadList()
        onActivity("Stopped “\(id)”.")
        return .stopped
    }

    /// Stops a container with the default options. UI-friendly overload so views never
    /// name the Backend `StopOptions` type (arch guard: UI must not import Backend).
    @discardableResult
    public func stop(id: String) async -> StopOutcome {
        await stop(id: id, options: .default)
    }

    /// Stops a container with explicit graceful options (timeout seconds + signal token),
    /// mapping them to `StopOptions` inside the domain.
    @discardableResult
    public func stop(id: String, timeout: Int?, signal: String?) async -> StopOutcome {
        await stop(id: id, options: StopOptions(timeout: timeout, signal: signal))
    }

    /// Interim Force Stop (hybrid): immediate force through the non-destructive stop verb
    /// (`stop -t 0`). The true destructive `kill` Force Stop with a confirmation sheet
    /// arrives in Milestone 5C.
    @discardableResult
    public func forceStop(id: String) async -> StopOutcome {
        await stop(id: id, options: .forced)
    }

    /// The hang notice: a working Force Stop (`.forced`) plus a `container kill` copy.
    public func makeHangNotice(id: String) -> LifecycleNotice {
        LifecycleNotice(
            detail: ErrorDetail(
                title: "Stop is taking longer than expected",
                explanation: "You can force the container to stop now, or copy the kill command.",
                recoveryActions: [.retryInTerminal(command: ["container", "kill", id])]),
            forceStopID: id)
    }

    /// Awaits `stopTask` or the hang timeout, whichever is first, WITHOUT cancelling the
    /// stop task. Returns `true` when the stop finished in time.
    private func raceAgainstHangTimeout(_ stopTask: Task<(any Error)?, Never>) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = await stopTask.value
                return true
            }
            group.addTask { [hangTimeout] in
                try? await Task.sleep(for: hangTimeout)
                return false
            }
            let first = await group.next() ?? true
            group.cancelAll()  // cancels only the wrapper tasks, never `stopTask` itself
            return first
        }
    }

    /// Container-level "already stopped / not running" is benign and must not be normalized
    /// into a daemon-unavailable error (ErrorNormalizer's daemon signatures include "not
    /// running"). Intercept the raw `BackendError` first.
    private func isBenignAlreadyStopped(_ error: any Error) -> Bool {
        guard case let BackendError.nonZeroExit(_, _, stderr) = error else { return false }
        let s = stderr.lowercased()
        let benign =
            s.contains("not running") || s.contains("already stopped")
            || s.contains("invalidstate") || s.contains("invalid state")
        let daemon =
            s.contains("xpc") || s.contains("launchd") || s.contains("connection refused")
        return benign && !daemon
    }

    /// Delete is idempotent: a `notFound` means the container is already gone, which is a
    /// benign success — distinct from the "already stopped" check used by stop/kill (a
    /// `notFound` on stop/kill stays a surfaced error). Daemon outages are never benign.
    private func isBenignAlreadyRemoved(_ error: any Error) -> Bool {
        guard case let BackendError.nonZeroExit(_, _, stderr) = error else { return false }
        let s = stderr.lowercased()
        let gone = s.contains("notfound") || s.contains("not found")
        let daemon =
            s.contains("xpc") || s.contains("launchd") || s.contains("connection refused")
        return gone && !daemon
    }

    // MARK: - Destructive (kill / delete / prune / export)

    /// Force-stops (kills) a container. The real destructive escalation for a hung stop.
    @discardableResult
    public func kill(id: String, signal: String? = nil) async -> StopOutcome {
        busy.insert(id)
        defer { busy.remove(id) }
        do {
            try await backend.killContainer(id: id, signal: signal)
            await reloadList()
            onActivity("Force-stopped “\(id)”.")
            return .stopped
        } catch {
            if isBenignAlreadyStopped(error) {
                onActivity("“\(id)” was already stopped.")
                return .alreadyStopped
            }
            let detail = normalize(error).detail
            notice = LifecycleNotice(detail: detail)
            return .failed(detail)
        }
    }

    public func killAll(ids: [String]) async {
        for id in ids { _ = await kill(id: id) }
    }

    public func delete(id: String, force: Bool) async {
        busy.insert(id)
        defer { busy.remove(id) }
        do {
            try await backend.removeContainer(id: id, force: force)
            await reloadList()
            onActivity("Deleted “\(id)”.")
        } catch {
            if isBenignAlreadyRemoved(error) {
                await reloadList()
                onActivity("“\(id)” was already removed.")
                return
            }
            notice = LifecycleNotice(detail: normalize(error).detail)
        }
    }

    public func deleteAll(ids: [String], force: Bool) async {
        for id in ids { await delete(id: id, force: force) }
    }

    /// The stopped containers a prune would remove (for the Cleanup sheet's precompute).
    public func computePruneTargets() async -> [Container] {
        let all = (try? await backend.listContainers(all: true)) ?? []
        return all.map(Container.init(summary:)).filter { $0.state != .running }
    }

    @discardableResult
    public func prune() async -> PruneSummary {
        do {
            let result = try await backend.pruneContainers()
            await reloadList()
            let message = result.reclaimedDescription ?? "Cleanup complete."
            onActivity(message)
            return PruneSummary(message: message)
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
            return PruneSummary(message: "Cleanup failed.")
        }
    }

    /// Whether the container is in a safe state to export (stopped). Running ⇒ warn first.
    public func validateExport(id: String) -> Bool {
        currentState(id) != .running
    }

    public func export(id: String, to url: URL) async {
        // With a task center wired, the export registers an Activity task: the long archive
        // write is visible, cancellable, and keeps its raw transcript on failure. Without
        // one (previews/tests), fall back to the inline notice path.
        guard let taskCenter else {
            busy.insert(id)
            defer { busy.remove(id) }
            do {
                try await backend.exportContainer(id: id, to: url)
                onActivity("Exported “\(id)” to \(url.lastPathComponent).")
            } catch {
                notice = LifecycleNotice(detail: normalize(error).detail)
            }
            return
        }
        busy.insert(id)
        let task = taskCenter.runAsync(
            kind: .export, title: "Export \(id)",
            invocation: CommandInvocation(CLICommand.exportContainer(id: id, to: url))
        ) { [backend] in try await backend.exportContainer(id: id, to: url) }
        await task.wait()
        busy.remove(id)
        if case .succeeded = task.state {
            onActivity("Exported “\(id)” to \(url.lastPathComponent).")
        }
    }

    // MARK: - Attach (read-only interim)

    public func beginAttach(id: String) {
        attachTask?.cancel()
        attachSession = AttachSession(phase: .streaming)
        attachTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await line in self.backend.followLogs(container: id) {
                    self.appendAttachLine(line)
                }
                self.attachSession?.phase = .ended
            } catch is CancellationError {
                // clean teardown
            } catch {
                let detail = self.normalize(error).detail
                self.attachSession?.phase = .failed(detail)
                self.notice = LifecycleNotice(
                    detail: ErrorDetail(
                        title: "Started, but couldn't attach",
                        explanation: detail.explanation,
                        recoveryActions: [.retry]),
                    offersShellHint: true)
            }
        }
    }

    public func retryAttach(id: String) { beginAttach(id: id) }

    public func detach() {
        attachTask?.cancel()
        attachTask = nil
        attachSession = nil
    }

    private func appendAttachLine(_ line: OutputLine) {
        nextLogLineID += 1
        attachSession?.append(LogLine(id: nextLogLineID, source: line.source, text: line.text))
    }
}
