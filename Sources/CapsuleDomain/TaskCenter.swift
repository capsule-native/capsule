//
//  TaskCenter.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The backing for
//  the Activity pane's Tasks/Progress tabs: long image operations (pull/push/save/load)
//  register an ``OperationTask`` that accumulates a transcript, records success/failure, and
//  can be retried. Milestone 7 will expand this into the full activity surface.

import CapsuleBackend
import Foundation
import Observation

/// The kind of long-running operation a task represents.
public enum OperationKind: String, Sendable, CaseIterable {
    case pull
    case push
    case save
    case load
    case build
    case run
    case export
    case systemStart
    case copy
    case machineCreate
    case systemKernelInstall

    public var title: String {
        switch self {
        case .pull: return "Pull"
        case .push: return "Push"
        case .save: return "Save"
        case .load: return "Load"
        case .build: return "Build"
        case .run: return "Run"
        case .export: return "Export"
        case .systemStart: return "Start Services"
        case .copy: return "Copy"
        case .machineCreate: return "Create Machine"
        case .systemKernelInstall: return "Install Kernel"
        }
    }

    public var symbolName: String {
        switch self {
        case .pull: return "arrow.down.circle"
        case .push: return "arrow.up.circle"
        case .save: return "square.and.arrow.down"
        case .load: return "square.and.arrow.up"
        case .build: return "hammer"
        case .run: return "play.rectangle"
        case .export: return "square.and.arrow.up.on.square"
        case .systemStart: return "power"
        case .copy: return "doc.on.doc"
        case .machineCreate: return "cpu"
        case .systemKernelInstall: return "cpu.fill"
        }
    }
}

/// One long-running operation: its live state, the accumulated transcript (UI-safe
/// ``LogLine``s, so the UI never sees a backend type), and a stable id.
@MainActor
@Observable
public final class OperationTask: Identifiable {
    public let id: String
    public let title: String
    public let kind: OperationKind
    public internal(set) var state: TaskState = .running(progress: nil)
    public internal(set) var transcript: [LogLine] = []
    /// Whether the task exposes a Stop control while active (all current kinds do; the flag
    /// keeps the door open for fire-and-forget jobs that cannot be interrupted).
    public internal(set) var isCancellable: Bool = true

    private var nextLineID = 0
    /// The Swift task currently driving this operation; `wait()` awaits it (used by tests
    /// and any caller that needs to act on completion).
    fileprivate var driver: Task<Void, Never>?

    init(id: String, title: String, kind: OperationKind) {
        self.id = id
        self.title = title
        self.kind = kind
    }

    /// The transcript joined into a single copyable string.
    public var transcriptText: String {
        transcript.map(\.text).joined(separator: "\n")
    }

    fileprivate func append(source: OutputLine.Source, text: String) {
        nextLineID += 1
        transcript.append(LogLine(id: nextLineID, source: source, text: text))
    }

    fileprivate func resetForRetry() {
        transcript = []
        nextLineID = 0
        state = .running(progress: nil)
    }

    /// Awaits the operation's completion.
    public func wait() async {
        await driver?.value
    }
}

@MainActor
@Observable
public final class TaskCenter {
    public private(set) var tasks: [OperationTask] = []

    private let normalize: @Sendable (any Error) -> CapsuleError
    private var streams: [String: @Sendable () -> AsyncThrowingStream<OutputLine, Error>] = [:]
    private var operations: [String: @Sendable () async throws -> Void] = [:]
    private var successHandlers: [String: @MainActor () async -> Void] = [:]
    private var counter = 0

    public init(
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize
    ) {
        self.normalize = normalize
    }

    /// The tasks still queued or running — the Progress tab's source.
    public var activeTasks: [OperationTask] { tasks.filter { $0.state.isActive } }

    /// Registers and starts a streaming operation (pull/push). Each yielded line is appended
    /// to the transcript; completion flips the state to succeeded/failed.
    @discardableResult
    public func runStreaming(
        kind: OperationKind,
        title: String,
        onSuccess: (@MainActor () async -> Void)? = nil,
        _ stream: @escaping @Sendable () -> AsyncThrowingStream<OutputLine, Error>
    ) -> OperationTask {
        let task = makeTask(kind: kind, title: title)
        streams[task.id] = stream
        successHandlers[task.id] = onSuccess
        tasks.append(task)
        drive(task)
        return task
    }

    /// Registers and starts a non-streaming operation (save/load). A thrown error is
    /// captured in the transcript and the state flips to failed.
    @discardableResult
    public func runAsync(
        kind: OperationKind,
        title: String,
        onSuccess: (@MainActor () async -> Void)? = nil,
        _ operation: @escaping @Sendable () async throws -> Void
    ) -> OperationTask {
        let task = makeTask(kind: kind, title: title)
        operations[task.id] = operation
        successHandlers[task.id] = onSuccess
        tasks.append(task)
        drive(task)
        return task
    }

    /// Re-runs a finished (typically failed or cancelled) task using its original operation.
    public func retry(_ task: OperationTask) {
        task.resetForRetry()
        drive(task)
    }

    /// Cancels a running task. Cancelling the driver `Task` propagates through the streaming
    /// `AsyncThrowingStream`'s `onTermination` (or the non-streaming runner's task
    /// cancellation), terminating the underlying child process; the driver catches the
    /// resulting `CancellationError` and records the neutral `.cancelled` state.
    public func cancel(_ task: OperationTask) {
        guard task.state.isActive, task.isCancellable else { return }
        task.driver?.cancel()
    }

    /// Drops every finished task (and its retained operation), leaving active ones.
    public func clearFinished() {
        let removed = tasks.filter { !$0.state.isActive }.map(\.id)
        for id in removed {
            streams[id] = nil
            operations[id] = nil
            successHandlers[id] = nil
        }
        tasks.removeAll { !$0.state.isActive }
    }

    // MARK: - Internals

    private func makeTask(kind: OperationKind, title: String) -> OperationTask {
        counter += 1
        return OperationTask(id: "task-\(counter)", title: title, kind: kind)
    }

    private func drive(_ task: OperationTask) {
        if let stream = streams[task.id] {
            task.driver = Task { @MainActor [weak self] in
                task.state = .running(progress: nil)
                do {
                    for try await line in stream() {
                        task.append(source: line.source, text: line.text)
                        if let fraction = ProgressParser.fraction(in: line.text) {
                            task.state = .running(progress: fraction)
                        }
                    }
                    try Task.checkCancellation()
                    await self?.successHandlers[task.id]?()
                    task.state = .succeeded
                } catch is CancellationError {
                    task.state = .cancelled
                } catch {
                    if Task.isCancelled {
                        task.state = .cancelled
                    } else {
                        self?.recordFailure(error, on: task)
                    }
                }
            }
        } else if let operation = operations[task.id] {
            task.driver = Task { @MainActor [weak self] in
                task.state = .running(progress: nil)
                do {
                    try await operation()
                    try Task.checkCancellation()
                    await self?.successHandlers[task.id]?()
                    task.state = .succeeded
                } catch is CancellationError {
                    task.state = .cancelled
                } catch {
                    if Task.isCancelled {
                        task.state = .cancelled
                    } else {
                        self?.recordFailure(error, on: task)
                    }
                }
            }
        }
    }

    private func recordFailure(_ error: any Error, on task: OperationTask) {
        let detail = normalize(error).detail
        task.append(source: .stderr, text: detail.explanation)
        task.state = .failed(detail.diagnosticInfo)
    }
}
