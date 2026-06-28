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
        settleDelay: Duration = .milliseconds(400)
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
