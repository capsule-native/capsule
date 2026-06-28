//
//  TerminalSurface.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The terminal-session port. CapsuleUI renders an embedded terminal through this seam,
//  receiving an erased view, so it never imports the engine (SwiftTerm/PTY live in
//  CapsuleTerminal, wired only by the composition root).

import CapsuleDomain
import SwiftUI

/// How an embedded terminal session ended.
public enum TerminalExitStatus: Sendable, Equatable {
    case exited(code: Int32)
    case signalled(signal: Int32)
    case failed(String)

    /// A short user-facing description for the "Session ended" banner.
    public var bannerText: String {
        switch self {
        case .exited(let code):
            return code == 0 ? "Session ended." : "Session ended (exit \(code))."
        case .signalled(let signal):
            return "Session ended (signal \(signal))."
        case .failed(let message):
            return message
        }
    }
}

/// Produces an embeddable terminal surface that spawns a `TerminalRequest`'s command in a
/// PTY. The concrete engine (SwiftTerm) lives in `CapsuleTerminal`; tests/previews use
/// `StubTerminalSurfaceProvider`.
@MainActor public protocol TerminalSurfaceProviding {
    func makeSurface(
        for request: TerminalRequest,
        onExit: @escaping (TerminalExitStatus) -> Void
    ) -> AnyView
}

/// A no-engine provider for previews and tests: renders a static placeholder.
public struct StubTerminalSurfaceProvider: TerminalSurfaceProviding {
    public nonisolated init() {}

    public func makeSurface(
        for request: TerminalRequest,
        onExit: @escaping (TerminalExitStatus) -> Void
    ) -> AnyView {
        AnyView(
            VStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(request.argv.joined(separator: " "))
                    .font(.system(.caption, design: .monospaced))
                Text("Terminal preview").foregroundStyle(.tertiary).font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }
}

/// Observable state for the single active embedded-terminal session. `generation` is the
/// SwiftUI identity used to rebuild the surface (and its PTY) on restart.
@MainActor
@Observable
public final class TerminalSessionState {
    public let request: TerminalRequest
    public private(set) var generation: Int = 0
    /// Set when the child process exits; drives the "Session ended" banner.
    public var exit: TerminalExitStatus?

    public init(request: TerminalRequest) {
        self.request = request
    }

    /// A SwiftUI identity for the terminal surface: unique per session instance and bumped
    /// on restart, so replacing the session (A→B) or restarting it rebuilds the PTY.
    public var surfaceID: String { "\(ObjectIdentifier(self))-\(generation)" }

    /// Re-launches the same command: clears the exit state and bumps the surface identity.
    public func restart() {
        exit = nil
        generation += 1
    }
}
