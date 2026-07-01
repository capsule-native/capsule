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

    private var invocation: CommandInvocation {
        lifecycle.execInvocation(id: containerID, command: CommandTokenizer.tokenize(command))
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

            CommandPreviewView(invocation)

            HStack {
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Open in Terminal.app") {
                    lifecycle.openInExternalTerminal(invocation.argv)
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
