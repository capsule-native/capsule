//
//  DiagnosticBundle.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// What a diagnostic bundle is permitted to capture.
///
/// The defaults encode Capsule's privacy posture: telemetry is **local-only** and full
/// command content is **not** captured. Both must be explicitly opted into.
public struct DiagnosticOptions: Sendable, Equatable, Codable {
    /// Capture full command argv + stderr (still secret-scrubbed). Off by default.
    public var includeCommandContent: Bool
    /// Permit uploading the bundle / crash reports off-device. Off by default.
    public var allowSubmission: Bool

    public init(includeCommandContent: Bool = false, allowSubmission: Bool = false) {
        self.includeCommandContent = includeCommandContent
        self.allowSubmission = allowSubmission
    }

    /// Local-only, content-free defaults.
    public static let `default` = DiagnosticOptions()
}

/// One command's entry in a diagnostic transcript: enough to triage a failure, with the
/// content gated behind an explicit opt-in.
public struct CommandTranscriptEntry: Sendable, Equatable, Codable {
    /// The command's argv. Replaced with a placeholder when content capture is off.
    public var command: [String]
    /// The command's exit code, if known.
    public var exitCode: Int32?
    /// The command's stderr. Replaced with a placeholder when content capture is off.
    public var stderr: String

    public init(command: [String], exitCode: Int32?, stderr: String) {
        self.command = command
        self.exitCode = exitCode
        self.stderr = stderr
    }

    /// A copy with command content removed but the exit code (a fact, not content) kept.
    public func redactingContent() -> CommandTranscriptEntry {
        CommandTranscriptEntry(
            command: ["‹command content omitted›"],
            exitCode: exitCode,
            stderr: stderr.isEmpty ? "" : "‹stderr omitted›"
        )
    }

    /// A copy keeping content but scrubbing credentials — used when content is opted in.
    public func scrubbingSecrets() -> CommandTranscriptEntry {
        CommandTranscriptEntry(
            command: SecretRedactor.redact(arguments: command),
            exitCode: exitCode,
            stderr: SecretRedactor.redact(stderr)
        )
    }
}

/// An exportable snapshot of everything support needs to triage a failure: app + runtime
/// versions, the host OS, recent log entries, and the failing command transcript.
///
/// A bundle is always safe to share: command content is omitted unless the user opted in,
/// and credentials are scrubbed even then.
public struct DiagnosticBundle: Sendable, Equatable, Codable {
    public var capsuleVersion: String
    public var containerSystemVersion: String?
    public var hostOSVersion: String
    public var logEntries: [String]
    public var commandTranscript: [CommandTranscriptEntry]
    /// Whether this bundle was built with command content captured.
    public var includesCommandContent: Bool

    public init(
        capsuleVersion: String,
        containerSystemVersion: String?,
        hostOSVersion: String,
        logEntries: [String],
        commandTranscript: [CommandTranscriptEntry],
        includesCommandContent: Bool
    ) {
        self.capsuleVersion = capsuleVersion
        self.containerSystemVersion = containerSystemVersion
        self.hostOSVersion = hostOSVersion
        self.logEntries = logEntries
        self.commandTranscript = commandTranscript
        self.includesCommandContent = includesCommandContent
    }

    /// Serializes the bundle to stable, human-readable JSON.
    public func exportedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Writes the bundle as `capsule-diagnostics.json` into `directory`, returning the
    /// created file URL.
    @discardableResult
    public func write(to directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("capsule-diagnostics.json")
        try exportedJSON().write(to: url, options: .atomic)
        return url
    }
}

/// Assembles a `DiagnosticBundle` from already-gathered inputs, applying the redaction
/// policy dictated by `DiagnosticOptions`.
///
/// The builder takes plain values rather than reading OSLog / spawning the CLI itself, so
/// it stays pure and testable; the composition root is responsible for gathering the
/// inputs (e.g. via `OSLogStore`, `ProcessInfo`, and the backend's `system version`).
public struct DiagnosticBundleBuilder: Sendable {
    public var capsuleVersion: String
    public var containerSystemVersion: String?
    public var hostOSVersion: String
    public var logEntries: [String]
    public var transcript: [CommandTranscriptEntry]

    public init(
        capsuleVersion: String,
        containerSystemVersion: String?,
        hostOSVersion: String,
        logEntries: [String],
        transcript: [CommandTranscriptEntry]
    ) {
        self.capsuleVersion = capsuleVersion
        self.containerSystemVersion = containerSystemVersion
        self.hostOSVersion = hostOSVersion
        self.logEntries = logEntries
        self.transcript = transcript
    }

    /// Builds the bundle, redacting (or, when opted in, secret-scrubbing) the transcript.
    public func build(options: DiagnosticOptions = .default) -> DiagnosticBundle {
        let processed =
            options.includeCommandContent
            ? transcript.map { $0.scrubbingSecrets() }
            : transcript.map { $0.redactingContent() }

        return DiagnosticBundle(
            capsuleVersion: capsuleVersion,
            containerSystemVersion: containerSystemVersion,
            hostOSVersion: hostOSVersion,
            logEntries: logEntries,
            commandTranscript: processed,
            includesCommandContent: options.includeCommandContent
        )
    }
}

extension DiagnosticBundleBuilder {
    /// The host macOS version string from `ProcessInfo`, e.g. `"macOS 26.0.0"`.
    public static func currentHostOSVersion() -> String {
        "macOS " + ProcessInfo.processInfo.operatingSystemVersionString
    }
}
