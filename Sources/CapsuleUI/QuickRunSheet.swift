//
//  QuickRunSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Quick Run sheet: image + name + dynamic port/env/volume rows + a command override and
//  the run toggles, with a live `container run …` command preview (the Run Inspector). An
//  interactive run hands off to the embedded terminal and dismisses; a detached run streams
//  its task transcript inline and, on failure, shows the triage panel.

import CapsuleDomain
import SwiftUI

struct QuickRunSheet: View {
    @Bindable var model: RunModel
    var onResolveImage: (String) -> Void
    var onClose: () -> Void

    @State private var activeTask: OperationTask?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    form
                    if let task = activeTask {
                        Divider()
                        runResult(task)
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 540, height: 620)
    }

    private var header: some View {
        HStack {
            Label("Run a Container", systemImage: "play.rectangle")
                .font(.headline)
            Spacer()
        }
        .padding(12)
    }

    @ViewBuilder
    private var form: some View {
        labeledField("Image", text: $model.draft.image, prompt: "alpine:latest")
        labeledField("Name", text: $model.draft.name, prompt: "optional")
        rowEditor("Ports", rows: $model.draft.portRows, example: "8080:80")
        rowEditor("Environment", rows: $model.draft.envRows, example: "KEY=value")
        rowEditor("Volumes", rows: $model.draft.volumeRows, example: "/host:/container")
        labeledField("Working dir", text: $model.draft.workdir, prompt: "optional")
        labeledField("Command", text: $model.draft.command, prompt: "optional override")

        VStack(alignment: .leading, spacing: 4) {
            Toggle("Interactive (open a TTY in the terminal)", isOn: $model.draft.interactive)
            Toggle("Remove on exit (--rm)", isOn: $model.draft.remove)
            Toggle("Detach (run in background)", isOn: $model.draft.detach)
                .disabled(model.draft.interactive)
        }

        CommandPreviewView(model.commandInvocation)
    }

    @ViewBuilder
    private func runResult(_ task: OperationTask) -> some View {
        if case .failed = task.state {
            RunFailureTriageView(
                task: task,
                imageReference: model.resolveImageReference,
                onResolveImage: {
                    if let ref = model.resolveImageReference { onResolveImage(ref) }
                },
                onRetryInTerminal: {
                    model.retryInTerminal()
                    onClose()
                })
        } else {
            TaskTranscriptView(task: task)
        }
    }

    private var footer: some View {
        HStack {
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(model.draft.interactive ? "Run in Terminal" : "Run") {
                run()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.draft.image.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
    }

    private func run() {
        if model.draft.interactive {
            model.runInTerminal()
            onClose()
        } else {
            activeTask = model.runDetached()
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
        }
    }

    private func rowEditor(
        _ label: String, rows: Binding<[String]>, example: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    rows.wrappedValue.append("")
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help("Add a \(label.lowercased()) row")
            }
            ForEach(rows.wrappedValue.indices, id: \.self) { index in
                HStack {
                    TextField(example, text: rows[index])
                        .textFieldStyle(.roundedBorder)
                    Button {
                        rows.wrappedValue.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}
