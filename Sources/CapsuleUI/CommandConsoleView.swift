//
//  CommandConsoleView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Command Console: an editable `container …` command field seeded from the current
//  best-fit invocation. It backs both the standalone raw-command-preview action and the
//  universal terminal passthrough — copy the command, or escalate it to the embedded terminal
//  or the external Terminal.app. The seed text is the redacted display string; the argv handed
//  to the terminals is the raw, re-tokenized command.

import AppKit
import CapsuleDomain
import SwiftUI

public struct CommandConsoleView: View {
    private let onRunEmbedded: (TerminalRequest) -> Void
    private let onRunExternal: ([String]) -> Void
    private let onClose: () -> Void

    @State private var text: String

    public init(
        seed: CommandInvocation?,
        onRunEmbedded: @escaping (TerminalRequest) -> Void,
        onRunExternal: @escaping ([String]) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onRunEmbedded = onRunEmbedded
        self.onRunExternal = onRunExternal
        self.onClose = onClose
        _text = State(initialValue: Self.seedText(for: seed))
    }

    /// The initial editor text: a seed's redacted display, or a bare `"container "` prompt.
    public static func seedText(for seed: CommandInvocation?) -> String {
        seed?.displayString ?? "container "
    }

    /// The raw argv to run: tokenize the edited text, drop a leading `container` token if the
    /// user kept it, then prepend the canonical executable so the result is always
    /// `["container", …]`.
    public static func resolvedArgv(from text: String) -> [String] {
        var tokens = CommandTokenizer.tokenize(text)
        if tokens.first == "container" { tokens.removeFirst() }
        return ["container"] + tokens
    }

    /// Whether the edited command carries a subcommand (more than the bare executable).
    private var isRunnable: Bool { Self.resolvedArgv(from: text).count > 1 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Command Console", systemImage: "terminal")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Command").font(.caption).foregroundStyle(.secondary)
                TextField("Command", text: $text, prompt: Text("container "))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .labelsHidden()
                Text("Runs the exact argv in a terminal. Edit freely; secrets are not stored.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(
                        Self.resolvedArgv(from: text).joined(separator: " "), forType: .string)
                }
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Run in Terminal.app") {
                    onRunExternal(Self.resolvedArgv(from: text))
                    onClose()
                }
                .disabled(!isRunnable)
                Button("Run in Terminal") {
                    let argv = Self.resolvedArgv(from: text)
                    onRunEmbedded(
                        TerminalRequest(
                            containerID: nil,
                            title: argv.joined(separator: " "),
                            argv: argv,
                            kind: .runInteractive))
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isRunnable)
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}
