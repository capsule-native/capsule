//
//  ExecSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Runs a command in a running container. The interactive command opens in the embedded
//  AppKit terminal; the detach fallback opens the same command in Terminal.app. A live
//  command preview shows exactly what will run.

import CapsuleDomain
import SwiftUI

struct ExecSheet: View {
    let containerID: String
    let lifecycle: ContainerLifecycleModel
    var onClose: () -> Void

    @State private var command: String = "sh"

    private var argv: [String] {
        let tokens = CommandTokenizer.tokenize(command)
        return ["container", "exec", "-it", containerID] + (tokens.isEmpty ? ["sh"] : tokens)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Exec in \(containerID)", systemImage: "terminal")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Command").font(.caption).foregroundStyle(.secondary)
                TextField("Command", text: $command, prompt: Text("sh"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Command preview").font(.caption).foregroundStyle(.secondary)
                Text(argv.joined(separator: " "))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(CapsuleColors.activitySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Open in Terminal.app") {
                    lifecycle.openInExternalTerminal(argv)
                    onClose()
                }
                Button("Run") {
                    lifecycle.execShell(
                        id: containerID, command: CommandTokenizer.tokenize(command))
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}
