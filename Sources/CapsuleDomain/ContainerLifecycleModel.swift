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

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void
    private let reloadList: @MainActor () async -> Void
    private let currentState: @MainActor (String) -> ContainerState
    private let terminalAvailable: @MainActor () -> Bool
    private let copyCommand: @MainActor ([String]) -> Void
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
        self.settleAttempts = settleAttempts
        self.settleDelay = settleDelay
        self.hangTimeout = hangTimeout
    }

    /// Whether interactive affordances (Open Shell, real attach) are available yet.
    public var isTerminalAvailable: Bool { terminalAvailable() }

    /// Copies a command to the clipboard (the retry-in-terminal interim until M6).
    public func copyToTerminal(_ argv: [String]) { copyCommand(argv) }

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
                recoveryActions: [.retry, .retryInTerminal(command: ["container", "kill", id])]))
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
