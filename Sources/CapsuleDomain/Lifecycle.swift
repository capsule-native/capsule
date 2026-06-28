//
//  Lifecycle.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Domain value types for the non-destructive lifecycle (start/stop/stats). Backend wire
//  types (ContainerStatsSample, OutputLine) are mapped here so they never reach the UI.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`.

import CapsuleBackend
import Foundation

/// A single line of attach/log output. `stream` reflects the *`container logs` CLI
/// process's* stdout/stderr pipe, not the workload's — labelled honestly in the UI.
public struct LogLine: Sendable, Equatable, Identifiable {
    public enum Stream: Sendable, Equatable { case standard, error }
    public var id: Int
    public var stream: Stream
    public var text: String

    public init(id: Int, stream: Stream, text: String) {
        self.id = id
        self.stream = stream
        self.text = text
    }

    public init(id: Int, source: OutputLine.Source, text: String) {
        self.init(id: id, stream: source == .stderr ? .error : .standard, text: text)
    }
}

/// A read-only attach session: a live `logs --follow` stream. Interactive shells are a
/// separate facility (the embedded terminal); this stays read-only by design. `lines` is a
/// capped ring buffer.
public struct AttachSession: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case streaming, ended, failed(ErrorDetail) }
    public var phase: Phase
    public private(set) var lines: [LogLine]
    public let isReadOnly: Bool

    private let cap = 200

    public init(phase: Phase = .streaming, lines: [LogLine] = []) {
        self.phase = phase
        self.lines = lines
        self.isReadOnly = true
    }

    public mutating func append(_ line: LogLine) {
        lines.append(line)
        if lines.count > cap { lines.removeFirst(lines.count - cap) }
    }
}

/// The outcome of a start attempt. No `startedAttachmentFailed` — attach failure is a
/// separate channel (`AttachSession.phase`).
public enum ContainerStartResult: Sendable, Equatable {
    case started(attached: Bool)
    case createdButNotStarted
    case runFailed
    case failedBeforeExecution
    case backendUnavailable
    case interrupted

    public var operationStatus: OperationStatus {
        switch self {
        case .started: return .succeeded
        case .failedBeforeExecution: return .failedBeforeExecution
        // `createdButNotStarted` arises only when the `start` command ran and exited
        // non-zero (the container resource already existed), so it is a during-execution
        // failure — consistent with CapsuleError.commandFailed.status.
        case .createdButNotStarted, .runFailed: return .failedDuringExecution
        case .backendUnavailable: return .backendUnavailable
        case .interrupted: return .interruptedByUser
        }
    }
}

/// A user-facing lifecycle notice (non-fatal info or recoverable error).
public struct LifecycleNotice: Sendable, Equatable {
    public var detail: ErrorDetail
    public var offersShellHint: Bool
    /// When set, the notice offers a working "Force Stop" affordance for this container
    /// (the 5B hybrid interim, `stop -t 0`). The true destructive `kill` arrives in 5C.
    public var forceStopID: String?

    public init(detail: ErrorDetail, offersShellHint: Bool = false, forceStopID: String? = nil) {
        self.detail = detail
        self.offersShellHint = offersShellHint
        self.forceStopID = forceStopID
    }
}

/// A UI-facing summary of a prune (Cleanup) run, mapped from the backend `PruneResult` so no
/// Backend type reaches the UI.
public struct PruneSummary: Sendable, Equatable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}

/// The resolved outcome of a stop attempt.
public enum StopOutcome: Sendable, Equatable {
    case stopped
    case alreadyStopped
    case hung
    case failed(ErrorDetail)
}

/// Domain metrics for one container, mapped from a backend `ContainerStatsSample`. CPU% and
/// `capturedAt` are computed/stamped in the domain.
public struct ContainerMetrics: Sendable, Equatable, Identifiable {
    public var id: String
    public var cpuPercent: Double?
    public var memoryUsageBytes: UInt64?
    public var memoryLimitBytes: UInt64?
    public var networkRxBytes: UInt64?
    public var networkTxBytes: UInt64?
    public var blockReadBytes: UInt64?
    public var blockWriteBytes: UInt64?
    public var numProcesses: UInt64?
    public var capturedAt: Date

    /// Memory used as a percentage of the limit, when both are known.
    public var memoryPercent: Double? {
        guard let used = memoryUsageBytes, let limit = memoryLimitBytes, limit > 0 else {
            return nil
        }
        return Double(used) / Double(limit) * 100
    }

    public init(sample: ContainerStatsSample, capturedAt: Date, cpuPercent: Double?) {
        self.id = sample.id
        self.cpuPercent = cpuPercent
        self.memoryUsageBytes = sample.memoryUsageBytes
        self.memoryLimitBytes = sample.memoryLimitBytes
        self.networkRxBytes = sample.networkRxBytes
        self.networkTxBytes = sample.networkTxBytes
        self.blockReadBytes = sample.blockReadBytes
        self.blockWriteBytes = sample.blockWriteBytes
        self.numProcesses = sample.numProcesses
        self.capturedAt = capturedAt
    }
}
