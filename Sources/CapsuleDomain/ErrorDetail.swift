//
//  ErrorDetail.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. `ErrorDetail`
//  is the UI-facing presentation of an error; it lives in the domain so `CapsuleUI` can
//  render it without importing any backend or diagnostics module.

import Foundation

/// A presentation-ready view of an error: a short title, a fuller explanation, and an
/// ordered list of recovery actions to offer the user.
///
/// This is the reusable error-detail model the UI binds to. It is produced from a
/// `CapsuleError` via ``CapsuleError/detail`` (or from any raw `Error` via
/// `CapsuleDiagnostics.ErrorNormalizer`).
public struct ErrorDetail: Sendable, Equatable {
    /// A short, human-readable headline (one line).
    public var title: String
    /// A fuller explanation suitable for a secondary label.
    public var explanation: String
    /// Recovery actions in the order they should be presented (most useful first).
    public var recoveryActions: [RecoveryAction]

    public init(title: String, explanation: String, recoveryActions: [RecoveryAction] = []) {
        self.title = title
        self.explanation = explanation
        self.recoveryActions = recoveryActions
    }

    /// A lightweight bridge to the simpler `DiagnosticInfo` used by `TaskState`/`Outcome`.
    public var diagnosticInfo: DiagnosticInfo {
        DiagnosticInfo(summary: title, detail: explanation)
    }
}

extension CapsuleError {
    /// A presentation-ready `ErrorDetail` with an ordered list of recovery actions.
    public var detail: ErrorDetail {
        switch self {
        case let .daemonUnavailable(message, recovery):
            return ErrorDetail(
                title: "Container service unavailable",
                explanation: message,
                recoveryActions: recovery.isEmpty ? [.startServices, .openLogs] : recovery
            )

        case let .commandFailed(command, exitCode, stderr):
            if let code = exitCode, ProcessSignal.isUserInterruption(exitCode: code) {
                return ErrorDetail(
                    title: "Command interrupted",
                    explanation: "The command was interrupted before it finished.",
                    recoveryActions: [.retry, .retryInTerminal(command: command)]
                )
            }
            let codeSuffix = exitCode.map { " (exit code \($0))." } ?? "."
            let explanation =
                stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "The command failed\(codeSuffix)"
                : stderr
            return ErrorDetail(
                title: "Command failed",
                explanation: explanation,
                recoveryActions: [.retry, .retryInTerminal(command: command), .openLogs]
            )

        case let .interrupted(signal):
            let name = ProcessSignal(rawValue: signal)?.name ?? "signal \(signal)"
            return ErrorDetail(
                title: "Operation interrupted",
                explanation: "The operation was interrupted (\(name)).",
                recoveryActions: [.retry]
            )

        case let .invalidInput(field, message):
            return ErrorDetail(
                title: "Invalid input",
                explanation: "\(field): \(message)",
                recoveryActions: [.editConfiguration]
            )

        case let .permissionRequired(kind, message):
            return ErrorDetail(
                title: "\(kind.title) required",
                explanation: message,
                recoveryActions: [.grantPermission(kind), .openLogs]
            )

        case let .unsupportedFeature(message):
            return ErrorDetail(
                title: "Not supported",
                explanation: message,
                recoveryActions: [.exportDiagnostics]
            )

        case let .unknown(message):
            return ErrorDetail(
                title: "Something went wrong",
                explanation: message,
                recoveryActions: [.openLogs, .exportDiagnostics]
            )
        }
    }

    /// The normalized `OperationStatus` this error resolves to.
    public var status: OperationStatus {
        switch self {
        case .daemonUnavailable:
            return .backendUnavailable
        case let .commandFailed(_, exitCode, _):
            if let code = exitCode, ProcessSignal.isUserInterruption(exitCode: code) {
                return .interruptedByUser
            }
            return .failedDuringExecution
        case .interrupted:
            return .interruptedByUser
        case .invalidInput, .permissionRequired, .unsupportedFeature:
            return .failedBeforeExecution
        case .unknown:
            return .failedDuringExecution
        }
    }
}
