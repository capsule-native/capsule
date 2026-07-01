//
//  PrivacyDisclosure.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: Domain layer — no UI, no `Process`. This is the single source of truth for what the
//  in-app Privacy page states. It mirrors the posture already encoded by
//  `CapsuleDiagnostics.DiagnosticOptions` (local-only, content-free, opt-in submission) so the
//  words the user reads and the behavior the code enforces cannot drift apart.

import Foundation

/// A plain, testable description of Capsule's privacy posture: exactly what is collected and
/// what is never collected. Rendered verbatim by the Privacy page in Settings.
public struct PrivacyDisclosure: Sendable, Equatable {
    /// One disclosed fact — a headline plus a plain-language detail.
    public struct Item: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let detail: String

        public init(id: String, title: String, detail: String) {
            self.id = id
            self.title = title
            self.detail = detail
        }
    }

    /// What Capsule may collect — all local-only or explicitly opt-in.
    public let collected: [Item]
    /// What Capsule never collects.
    public let neverCollected: [Item]

    public init(collected: [Item], neverCollected: [Item]) {
        self.collected = collected
        self.neverCollected = neverCollected
    }

    /// The shipped disclosure. Kept in lockstep with `DiagnosticOptions.default` (local-only,
    /// content-free, submission off by default).
    public static let `default` = PrivacyDisclosure(
        collected: [
            Item(
                id: "local-logs",
                title: "Local diagnostic logs",
                detail:
                    "Capsule writes logs to the unified logging system (OSLog) on this Mac to help "
                    + "you diagnose failures. They stay on your device and are never uploaded."
            ),
            Item(
                id: "diagnostic-bundle",
                title: "Diagnostic bundles you export",
                detail:
                    "When you choose Export Diagnostics, Capsule assembles app + runtime versions, "
                    + "your macOS version, recent log lines, and the failing command's exit status. "
                    + "The file is written where you pick it and is shared only if you send it."
            ),
            Item(
                id: "crash-opt-in",
                title: "Crash reports (opt-in, off by default)",
                detail:
                    "Crash submission is disabled unless you explicitly turn it on. Nothing leaves "
                    + "your Mac until you opt in."
            ),
            Item(
                id: "preferences",
                title: "Your preferences",
                detail:
                    "Settings such as your terminal choice and update preference are stored in the "
                    + "standard macOS preferences for Capsule on this device."
            ),
        ],
        neverCollected: [
            Item(
                id: "no-secrets",
                title: "Secrets and credentials",
                detail:
                    "Registry passwords and tokens are passed to the runtime over stdin, never "
                    + "written to arguments, logs, or any exported bundle. Credentials are scrubbed "
                    + "even from opted-in content."
            ),
            Item(
                id: "no-command-content",
                title: "Command content, unless you approve it",
                detail:
                    "The full arguments and output of the commands Capsule runs are omitted from "
                    + "diagnostic bundles unless you explicitly opt in — and are still secret-scrubbed "
                    + "when you do."
            ),
            Item(
                id: "no-analytics",
                title: "Analytics or telemetry",
                detail:
                    "Capsule has no analytics, no tracking, and no usage reporting. There is no "
                    + "background phone-home."
            ),
        ]
    )
}
