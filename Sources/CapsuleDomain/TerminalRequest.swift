//
//  TerminalRequest.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. A pure description
//  of a command to run in the embedded terminal; the engine that spawns it lives in
//  CapsuleTerminal, reached only through an injected seam.

/// A request to run a command in the embedded terminal. Pure data: no view, no process.
public struct TerminalRequest: Sendable, Equatable {
    /// Why the terminal is being opened (drives titles/telemetry; not behavior).
    public enum Kind: String, Sendable, Equatable {
        case execShell
        case interactiveAttach
        case retry
    }

    /// The container this terminal targets, when applicable.
    public let containerID: String?
    /// A short human-readable title for the session.
    public let title: String
    /// The full command to run, including the executable name (e.g. `["container", …]`).
    public let argv: [String]
    public let kind: Kind

    public init(containerID: String?, title: String, argv: [String], kind: Kind) {
        self.containerID = containerID
        self.title = title
        self.argv = argv
        self.kind = kind
    }
}
