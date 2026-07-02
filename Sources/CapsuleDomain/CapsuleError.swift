//
//  CapsuleError.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. `CapsuleError`
//  is the single, normalized error currency of the app; adapters map their raw failures
//  into it (see `CapsuleDiagnostics.ErrorNormalizer`).

import Foundation

/// A kind of permission an operation may require before it can proceed.
public enum PermissionKind: String, Sendable, Equatable, Hashable, Codable {
    /// Administrator / `sudo` rights.
    case administrator
    /// Access to a file or directory outside the app's sandbox.
    case fileAccess
    /// Outbound network access (e.g. to a registry).
    case network

    /// A short, human-readable label for the permission.
    public var title: String {
        switch self {
        case .administrator: return "Administrator access"
        case .fileAccess: return "File access"
        case .network: return "Network access"
        }
    }
}

/// A concrete remedy the UI can offer the user in response to an error.
///
/// Recovery actions are *data*, not closures, so they can be rendered, logged, and
/// tested. The composition root maps each case onto a real handler.
public enum RecoveryAction: Sendable, Equatable, Hashable {
    /// Re-run the same operation from within the app.
    case retry
    /// Re-run the failing command in a terminal, where the user can inspect it.
    case retryInTerminal(command: [String])
    /// Start the container system services.
    case startServices
    /// Download and install the container CLI (missing-binary recovery).
    case installContainerCLI
    /// Open the diagnostic log viewer.
    case openLogs
    /// Open the relevant configuration for editing.
    case editConfiguration
    /// Export a diagnostic bundle for support.
    case exportDiagnostics
    /// Prompt the user to grant a required permission.
    case grantPermission(PermissionKind)

    /// A short, human-readable label for a button.
    public var title: String {
        switch self {
        case .retry: return "Try Again"
        case .retryInTerminal: return "Retry in Terminal"
        case .startServices: return "Start Services"
        case .installContainerCLI: return "Install container…"
        case .openLogs: return "Open Logs"
        case .editConfiguration: return "Edit Configuration"
        case .exportDiagnostics: return "Export Diagnostics"
        case let .grantPermission(kind): return "Grant \(kind.title)"
        }
    }
}

/// The single normalized error type the whole app speaks.
///
/// The `container` CLI fails in uneven ways — daemon outages, non-zero exits with terse
/// stderr, signal kills, validation rejections. Adapters translate all of those into one
/// of these cases so the domain and UI never have to reason about raw process failure.
public enum CapsuleError: Error, Sendable, Equatable {
    /// The container service / daemon is not reachable.
    case daemonUnavailable(message: String, recovery: [RecoveryAction])
    /// The `container` CLI binary itself is not installed (distinct from an
    /// installed-but-unreachable service, so the UI can offer installation).
    case cliNotInstalled(message: String, recovery: [RecoveryAction])
    /// A CLI command exited non-zero. `exitCode` is optional because a signal kill or a
    /// failure to spawn may leave us without one.
    case commandFailed(command: [String], exitCode: Int32?, stderr: String)
    /// The operation was interrupted by a signal (e.g. the user pressed Ctrl-C).
    case interrupted(signal: Int32)
    /// User-supplied input failed validation before anything ran.
    case invalidInput(field: String, message: String)
    /// The operation needs a permission that has not been granted.
    case permissionRequired(kind: PermissionKind, message: String)
    /// The requested capability is not supported by this backend / version.
    case unsupportedFeature(message: String)
    /// A failure that could not be mapped to a more specific case.
    case unknown(message: String)
}
