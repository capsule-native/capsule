//
//  BuildSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Build sheet: drag/drop (or choose) a context folder, set a tag + optional Dockerfile +
//  build-args, pick a preset, and stream the build. Raw stdout/stderr is NEVER hidden — the
//  full transcript stays visible, is exportable, and a "plain progress" retry re-runs the
//  build with --progress plain for diagnosis.

import AppKit
import CapsuleDomain
import SwiftUI
import UniformTypeIdentifiers

struct BuildSheet: View {
    @Bindable var model: BuildModel
    var onClose: () -> Void

    @State private var activeTask: OperationTask?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Build an Image", systemImage: "hammer")
                    .font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    dropZone
                    labeledField("Tag (required)", text: $model.draft.tag, prompt: "app:dev")
                    labeledField(
                        "Dockerfile", text: $model.draft.dockerfile, prompt: "optional path")
                    rowEditor("Build args", rows: $model.draft.buildArgRows, example: "KEY=value")
                    HStack(spacing: 16) {
                        Picker("Preset", selection: $model.draft.preset) {
                            ForEach(BuildPreset.allCases) { Text($0.title).tag($0) }
                        }
                        .fixedSize()
                        Toggle("No cache", isOn: $model.draft.noCache)
                    }
                    CommandPreviewView(model.commandInvocation)
                    if let task = activeTask {
                        Divider()
                        TaskTranscriptView(task: task)
                        transcriptActions(task)
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 640)
    }

    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Build context").font(.caption).foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
                .frame(height: 64)
                .overlay {
                    HStack {
                        Image(systemName: "folder")
                        Text(model.draft.contextDirectory?.path ?? "Drag a folder here, or Choose…")
                            .font(.callout)
                            .foregroundStyle(
                                model.draft.contextDirectory == nil ? .secondary : .primary
                            )
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseFolder() }
                    }
                    .padding(.horizontal, 12)
                }
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    loadDroppedFolder(providers)
                }
        }
    }

    @ViewBuilder
    private func transcriptActions(_ task: OperationTask) -> some View {
        HStack {
            Button("Export Transcript…") { exportTranscript(task) }
                .disabled(task.transcript.isEmpty)
            if case .failed = task.state {
                Button("Retry with Plain Progress") { activeTask = model.retryPlain() }
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Build") { activeTask = model.build() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canBuild)
        }
        .padding(12)
    }

    private var canBuild: Bool {
        model.draft.contextDirectory != nil
            && !model.draft.tag.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose Build Context"
        if panel.runModal() == .OK, let url = panel.url {
            model.draft.contextDirectory = url
        }
    }

    private func loadDroppedFolder(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            // If a file was dropped, use its containing folder as the context.
            let folder = isDirectory.boolValue ? url : url.deletingLastPathComponent()
            Task { @MainActor in model.draft.contextDirectory = folder }
        }
        return true
    }

    private func exportTranscript(_ task: OperationTask) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "build-transcript.txt"
        panel.allowedContentTypes = [.plainText, .log]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? task.transcriptText.write(to: url, atomically: true, encoding: .utf8)
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
