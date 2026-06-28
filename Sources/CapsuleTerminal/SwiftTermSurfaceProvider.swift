//
//  SwiftTermSurfaceProvider.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The embedded-terminal engine. All SwiftTerm/PTY/subprocess code lives here, behind the
//  CapsuleUI `TerminalSurfaceProviding` port. Wired only by the composition root; never
//  imported by CapsuleDomain or CapsuleUI (arch guard).

import AppKit
import CapsuleDomain
import CapsuleUI
import SwiftTerm
import SwiftUI

/// Produces a SwiftTerm-backed terminal surface that spawns a `TerminalRequest` in a PTY.
public struct SwiftTermSurfaceProvider: TerminalSurfaceProviding {
    /// Maps a logical argv[0] (e.g. "container") to an absolute executable path. The
    /// composition root supplies the resolved `container` location; anything else passes
    /// through unchanged (and is resolved by the spawn against PATH).
    private let executablePath: (String) -> String

    public init(executablePath: @escaping (String) -> String = { $0 }) {
        self.executablePath = executablePath
    }

    public func makeSurface(
        for request: TerminalRequest,
        onExit: @escaping (TerminalExitStatus) -> Void
    ) -> AnyView {
        AnyView(
            SwiftTermSurface(
                request: request, executablePath: executablePath, onExit: onExit))
    }
}

/// Hosts a `LocalProcessTerminalView` (an NSView) in SwiftUI and starts the request's
/// command in a pseudo-terminal.
private struct SwiftTermSurface: NSViewRepresentable {
    let request: TerminalRequest
    let executablePath: (String) -> String
    let onExit: (TerminalExitStatus) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onExit: onExit) }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        let argv = request.argv
        let executable = executablePath(argv.first ?? "/bin/sh")
        let args = Array(argv.dropFirst())
        view.startProcess(executable: executable, args: args)
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private let onExit: (TerminalExitStatus) -> Void

        init(onExit: @escaping (TerminalExitStatus) -> Void) {
            self.onExit = onExit
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            if let exitCode {
                onExit(.exited(code: exitCode))
            } else {
                onExit(.failed("The process ended unexpectedly."))
            }
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}
