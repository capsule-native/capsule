//
//  ProcessSignal.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. These are pure
//  value types describing POSIX signal conventions; process execution lives in
//  `CapsuleCLIBackend`.

import Foundation

/// The POSIX signals Capsule treats as a user-initiated interruption of an operation.
///
/// We normalize a signal into a shell-conventional exit code (`128 + signal`) so that
/// command exit codes, signal kills, and reported interruptions all collapse onto the
/// same truth. A SIGINT (2) becomes `130`; a SIGTERM (15) becomes `143`.
public enum ProcessSignal: Int32, Sendable, Equatable, CaseIterable {
    /// `SIGINT` — typically Ctrl-C.
    case interrupt = 2
    /// `SIGTERM` — a polite termination request.
    case terminate = 15

    /// The conventional name (`"SIGINT"`, `"SIGTERM"`) for logs and transcripts.
    public var name: String {
        switch self {
        case .interrupt: return "SIGINT"
        case .terminate: return "SIGTERM"
        }
    }

    /// The conventional shell exit code for a process killed by this signal: `128 + signal`.
    public var exitCode: Int32 { Self.exitCode(forSignal: rawValue) }

    /// The conventional shell exit code for *any* signal number: `128 + signal`.
    public static func exitCode(forSignal signal: Int32) -> Int32 { 128 + signal }

    /// The signal number encoded by a `128 + signal` exit code, or `nil` when `exitCode`
    /// is not signal-shaped (`<= 128`).
    public static func signal(forExitCode exitCode: Int32) -> Int32? {
        exitCode > 128 ? exitCode - 128 : nil
    }

    /// True when `exitCode` corresponds to a SIGINT (`130`) or SIGTERM (`143`) — i.e. the
    /// operation was interrupted by the user rather than failing on its own.
    public static func isUserInterruption(exitCode: Int32) -> Bool {
        exitCode == interrupt.exitCode || exitCode == terminate.exitCode
    }
}
