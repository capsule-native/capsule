//
//  ErrorNormalization.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import CapsuleDomain
import Foundation

/// Normalizes arbitrary `Error` values into the app's single error currency.
///
/// `CapsuleError` and its presentation (`ErrorDetail`) live in `CapsuleDomain` so the UI
/// can render them; this is the seam that turns *any* raw error — including ones an
/// adapter could not classify — into that currency.
public enum ErrorNormalizer {
    /// Substrings in a backend's stderr (or command) that signal the *service itself* is
    /// down or never came up — an XPC / launchd / connection failure — rather than a
    /// normal command rejection. When any appears we route the user to Start Services +
    /// diagnostics instead of presenting a generic "command failed".
    private static let daemonSignatures = [
        "connection refused",
        "could not connect",
        "failed to connect",
        "not running",
        "xpc",
        "launchd",
        "apiserver",
        "no such file or directory",
    ]

    private static func hasDaemonSignature(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return daemonSignatures.contains { lowered.contains($0) }
    }

    /// Substrings in a backend's stderr (or command) that signal the operation requires
    /// administrator privileges (e.g. `system dns create/delete`). The CLI prints
    /// `(try sudo?)` on a privileged-command failure, and its help reads "must run as an
    /// administrator". Checked AHEAD of the daemon signatures so an admin-gated failure maps
    /// to a clean permission prompt rather than a generic outage.
    private static let administratorSignatures = [
        "try sudo?",
        "must run as an administrator",
    ]

    private static func hasAdministratorSignature(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return administratorSignatures.contains { lowered.contains($0) }
    }

    /// Maps any `Error` to a `CapsuleError`.
    ///
    /// A value that is already a `CapsuleError` passes through unchanged; a
    /// ``BackendError`` is classified (daemon outage vs. command failure vs. decode vs.
    /// unimplemented); anything else is wrapped as `.unknown`, preferring a
    /// `LocalizedError`'s description when available.
    public static func normalize(_ error: Error) -> CapsuleError {
        if let capsule = error as? CapsuleError {
            return capsule
        }
        if let backend = error as? BackendError {
            return normalizeBackendError(backend)
        }
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return .unknown(message: message)
    }

    /// Classifies a raw ``BackendError`` into the app's normalized currency.
    private static func normalizeBackendError(_ error: BackendError) -> CapsuleError {
        switch error {
        case let .executableNotFound(path):
            return .cliNotInstalled(
                message: "The container CLI could not be found at \(path).",
                recovery: [.installContainerCLI, .openLogs]
            )

        case let .nonZeroExit(command, code, stderr):
            if hasAdministratorSignature(stderr) || hasAdministratorSignature(command) {
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .permissionRequired(
                    kind: .administrator,
                    message: trimmed.isEmpty
                        ? "This operation requires administrator privileges." : trimmed
                )
            }
            if hasDaemonSignature(stderr) || hasDaemonSignature(command) {
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .daemonUnavailable(
                    message: trimmed.isEmpty
                        ? "The container service is not reachable." : trimmed,
                    recovery: [.startServices, .openLogs, .exportDiagnostics]
                )
            }
            return .commandFailed(
                command: command.split(separator: " ").map(String.init),
                exitCode: code,
                stderr: stderr
            )

        case let .decodingFailed(message):
            return .unknown(message: message)

        case let .notImplemented(message):
            return .unsupportedFeature(message: message)
        }
    }

    /// Maps any `Error` to a presentation-ready `ErrorDetail` with recovery actions.
    public static func detail(for error: Error) -> ErrorDetail {
        normalize(error).detail
    }

    /// A lightweight `DiagnosticInfo` bridge for the simpler `TaskState`/`Outcome` paths.
    public static func diagnosticInfo(for error: Error) -> DiagnosticInfo {
        detail(for: error).diagnosticInfo
    }
}
