//
//  OperationStatus.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. These are pure
//  value types that normalize the CLI's uneven failure behavior into one truth.

import Foundation

/// Where in an operation's lifecycle a failure occurred.
///
/// The distinction matters because the recovery story differs: a `.beforeExecution`
/// failure (bad arguments, daemon down, executable missing) never touched any container
/// state, while a `.duringExecution` failure happened mid-flight and may have left
/// partial state behind.
public enum ExecutionPhase: String, Sendable, Equatable, Codable {
    case beforeExecution
    case duringExecution
}

/// The last observed runtime state of a container, kept *separate* from any exit code.
///
/// `container` API snapshots do not reliably expose a container's last runtime exit code,
/// so we never infer state from an exit code or vice-versa.
public enum ContainerRuntimeState: String, Sendable, Equatable, Codable {
    case unknown
    case created
    case running
    case stopped
    case exited
}

/// A raw observation of a single command invocation, modeling **command exit**, **task
/// exit**, and **container runtime state** as three independent fields.
///
/// They are intentionally not collapsed into one number: the `container` CLI's command
/// can succeed while the task inside the container exits non-zero, and the API snapshot
/// may report a runtime state that matches neither. `OperationStatus/resolve(_:)` reduces
/// an observation to a single normalized status without throwing away the underlying
/// fields.
public struct CommandObservation: Sendable, Equatable {
    /// The phase the operation reached.
    public var phase: ExecutionPhase
    /// Exit code of the `container` CLI process itself.
    public var commandExitCode: Int32?
    /// Exit code of the task running *inside* the container, when known. May differ from,
    /// or be unknown despite, the command exit code.
    public var taskExitCode: Int32?
    /// The container's last observed runtime state, when known.
    public var containerRuntimeState: ContainerRuntimeState?
    /// The signal that terminated the command, when the process was killed by one.
    public var signal: Int32?
    /// Whether the command emitted warnings despite succeeding.
    public var hasWarnings: Bool
    /// Whether the backend (the container service / daemon) was unavailable.
    public var backendUnavailable: Bool
    /// Whether the underlying state change succeeded but a follow-on attach/stream failed.
    public var attachmentFailed: Bool

    public init(
        phase: ExecutionPhase = .duringExecution,
        commandExitCode: Int32? = nil,
        taskExitCode: Int32? = nil,
        containerRuntimeState: ContainerRuntimeState? = nil,
        signal: Int32? = nil,
        hasWarnings: Bool = false,
        backendUnavailable: Bool = false,
        attachmentFailed: Bool = false
    ) {
        self.phase = phase
        self.commandExitCode = commandExitCode
        self.taskExitCode = taskExitCode
        self.containerRuntimeState = containerRuntimeState
        self.signal = signal
        self.hasWarnings = hasWarnings
        self.backendUnavailable = backendUnavailable
        self.attachmentFailed = attachmentFailed
    }
}

/// The normalized outcome of an operation.
///
/// Deliberately richer than a boolean or a raw exit code: a raw exit code is *not* the
/// sole source of truth, because the CLI reports interruptions, daemon outages, and
/// partial state changes in ways a single integer cannot capture.
public enum OperationStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case succeeded
    case succeededWithWarnings
    case failedBeforeExecution
    case failedDuringExecution
    case interruptedByUser
    case backendUnavailable
    case stateChangedButAttachmentFailed

    /// Whether the operation achieved its goal (with or without warnings).
    public var isSuccess: Bool {
        self == .succeeded || self == .succeededWithWarnings
    }

    /// Reduces a three-field observation to a single normalized status.
    ///
    /// Precedence (highest first):
    /// 1. **Interruption** — a SIGINT/SIGTERM signal, or a `130`/`143` exit code, always
    ///    means the user interrupted the work, regardless of anything else observed.
    /// 2. **Backend unavailable** — the service never accepted the command.
    /// 3. **Failed before execution** — validation/spawn failures that never ran.
    /// 4. **State changed but attachment failed** — the mutation landed; the follow-on
    ///    attach/stream did not.
    /// 5. **Failed during execution** — the command ran and exited non-zero.
    /// 6. **Succeeded** (with warnings when the command emitted any).
    public static func resolve(_ observation: CommandObservation) -> OperationStatus {
        if let signal = observation.signal,
            signal == ProcessSignal.interrupt.rawValue || signal == ProcessSignal.terminate.rawValue
        {
            return .interruptedByUser
        }
        if let code = observation.commandExitCode, ProcessSignal.isUserInterruption(exitCode: code)
        {
            return .interruptedByUser
        }
        if observation.backendUnavailable {
            return .backendUnavailable
        }
        if observation.phase == .beforeExecution {
            return .failedBeforeExecution
        }
        if observation.attachmentFailed {
            return .stateChangedButAttachmentFailed
        }
        if let code = observation.commandExitCode, code != 0 {
            return .failedDuringExecution
        }
        return observation.hasWarnings ? .succeededWithWarnings : .succeeded
    }
}
