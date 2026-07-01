//
//  CommandInvocation.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  An executable-aware command value: the faithful argv Capsule will run (or just ran),
//  shared by every preview / console / terminal path. `argv`/`rawDisplay` are the RAW real
//  argv (execution + embedded/external terminal); `displayString` is the operation-aware
//  REDACTED form used for all on-screen display and the copy button.

import Foundation

public struct CommandInvocation: Sendable, Equatable {
    /// The executable name — "container" by default. Display only; the runner owns the URL.
    public let executable: String
    /// The faithful argv after the executable (no redaction).
    public let arguments: [String]

    public init(_ arguments: [String], executable: String = "container") {
        self.executable = executable
        self.arguments = arguments
    }

    /// Raw argv (executable first) — for execution and `TerminalRequest`.
    public var argv: [String] { [executable] + arguments }

    /// Raw, space-joined command line — NOT redacted; the Command Console / terminal seed.
    public var rawDisplay: String { ([executable] + arguments).joined(separator: " ") }

    /// Redacted, space-joined command line — every on-screen display and the copy button.
    public var displayString: String { CommandRedactor.redactedDisplay(self) }
}
