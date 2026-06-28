//
//  CopySheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Copy files between the host and a container. A host panel (drop target + Choose…) and a
//  container panel (`id:/abs/path` with a Browse disclosure backed by a best-effort `ls`)
//  sit either side of a direction control. The container-path semantics are validated and
//  illustrated with an example before the Copy runs as a `.copy` Activity task.

import AppKit
import CapsuleDomain
import SwiftUI

struct CopySheet: View {
    @Bindable var model: CopyModel
    var onClose: () -> Void

    @State private var activeTask: OperationTask?
    @State private var isHostTargeted = false
    @State private var browseEntries: [ContainerFileItem] = []
    @State private var browsePath = "/"
    @State private var isBrowsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Copy Files", systemImage: "doc.on.doc")
                    .font(.headline)
                Spacer()
            }

            Picker("Direction", selection: $model.direction) {
                ForEach(CopyDirection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            hostPanel
            containerPanel

            if let message = model.validationMessage {
                Label(message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let task = activeTask {
                TaskTranscriptView(task: task)
            }

            HStack {
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Copy") { activeTask = model.copy() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCopy)
            }
        }
        .padding(16)
        .frame(width: 520, height: 560)
    }

    private var hostPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Host").font(.caption).foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isHostTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
                .frame(height: 56)
                .overlay {
                    HStack {
                        Image(systemName: "macwindow")
                        Text(model.hostURL?.path ?? "Drag a file here, or Choose…")
                            .foregroundStyle(model.hostURL == nil ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseHost() }
                    }
                    .padding(.horizontal, 12)
                }
                .onDrop(of: [.fileURL], isTargeted: $isHostTargeted) { providers in
                    loadDroppedHostURL(providers)
                }
        }
    }

    private var containerPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Container").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("container id", text: $model.containerID)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                Text(":").foregroundStyle(.secondary)
                TextField("/app/file", text: $model.containerPath)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Example: \(model.exampleID):/app/file")
                .font(.caption2)
                .foregroundStyle(.secondary)

            DisclosureGroup("Browse", isExpanded: $isBrowsing) {
                browseList
            }
            .onChange(of: isBrowsing) { _, expanded in
                if expanded { Task { await reloadBrowse(path: browsePath) } }
            }
        }
    }

    private var browseList: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(browsePath).font(.system(.caption, design: .monospaced))
                Spacer()
                Button("Up") {
                    let parent = (browsePath as NSString).deletingLastPathComponent
                    Task { await reloadBrowse(path: parent.isEmpty ? "/" : parent) }
                }
                .disabled(browsePath == "/")
            }
            if browseEntries.isEmpty {
                Text("No entries (the container must be running with ls).")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(browseEntries) { entry in
                    Button {
                        selectEntry(entry)
                    } label: {
                        HStack {
                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                            Text(entry.name)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 160)
    }

    private func selectEntry(_ entry: ContainerFileItem) {
        let joined = (browsePath as NSString).appendingPathComponent(entry.name)
        if entry.isDirectory {
            Task { await reloadBrowse(path: joined) }
        } else {
            model.containerPath = joined
        }
    }

    private func reloadBrowse(path: String) async {
        browsePath = path
        browseEntries = await model.browse(path: path)
    }

    private func chooseHost() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose a File or Folder"
        if panel.runModal() == .OK, let url = panel.url {
            model.hostURL = url
        }
    }

    private func loadDroppedHostURL(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in model.hostURL = url }
        }
        return true
    }
}
