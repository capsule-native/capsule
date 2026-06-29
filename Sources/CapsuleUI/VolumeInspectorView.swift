//
//  VolumeInspectorView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The volumes inspector: a Summary tab (name, source, size, created, and the prominent
//  attached-containers list) plus a Raw JSON tab fed by `volume inspect`. The raw payload is
//  always shown even when decoding drifts, and is copyable. AppKit (NSPasteboard) is
//  permitted in the UI layer.

import AppKit
import CapsuleDomain
import SwiftUI

struct VolumeInspectorView: View {
    let model: VolumeBrowserModel

    @State private var rawJSON = ""
    @State private var isLoadingRaw = false

    init(model: VolumeBrowserModel) {
        self.model = model
    }

    /// The single selected volume, when exactly one row is selected.
    private var solo: Volume? {
        guard model.selection.count == 1, let id = model.selection.first else { return nil }
        return model.selectedVolumes.first { $0.id == id }
    }

    var body: some View {
        TabView {
            summaryTab
                .tabItem { Label("Summary", systemImage: "info.circle") }
            rawTab
                .tabItem { Label("Raw JSON", systemImage: "curlybraces") }
        }
        .task(id: model.selection) { await loadRaw() }
    }

    // MARK: Summary

    @ViewBuilder
    private var summaryTab: some View {
        if model.selection.isEmpty {
            ContentUnavailableView(
                "No Selection", systemImage: "externaldrive",
                description: Text("Select a volume to see its details."))
        } else if let volume = solo {
            Form {
                Section("Volume") {
                    LabeledContent("Name", value: volume.name)
                    LabeledContent("Source", value: volume.source ?? "—")
                    LabeledContent("Size") {
                        if let bytes = volume.sizeBytes {
                            Text(bytes, format: .byteCount(style: .file))
                        } else {
                            Text("—")
                        }
                    }
                    if let created = volume.createdAt {
                        LabeledContent("Created") { Text(created, format: .dateTime) }
                    }
                }

                Section("Attached containers (\(volume.attachedContainers.count))") {
                    if volume.attachedContainers.isEmpty {
                        Text("Not mounted by any container.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(volume.attachedContainers, id: \.self) { name in
                            Text(name)
                        }
                    }
                }

                if !volume.options.isEmpty {
                    Section("Driver options") {
                        ForEach(volume.options.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                            LabeledContent(pair.key, value: pair.value)
                        }
                    }
                }

                if !volume.labels.isEmpty {
                    Section("Labels") {
                        ForEach(volume.labels.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                            LabeledContent(pair.key, value: pair.value)
                        }
                    }
                }

                Section {
                    Button {
                        Pasteboard.copy(volume.name)
                    } label: {
                        Label("Copy Name", systemImage: "doc.on.doc")
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "\(model.selection.count) Volumes Selected",
                systemImage: "externaldrive",
                description: Text("Select a single volume to see its details."))
        }
    }

    // MARK: Raw JSON

    @ViewBuilder
    private var rawTab: some View {
        if solo == nil {
            ContentUnavailableView(
                "No Selection", systemImage: "curlybraces",
                description: Text("Select a single volume to inspect its raw JSON."))
        } else {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        Pasteboard.copy(rawJSON)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .disabled(rawJSON.isEmpty)
                }
                .padding(8)

                Divider()

                ScrollView([.vertical, .horizontal]) {
                    Text(rawJSON.isEmpty ? "No raw payload available." : rawJSON)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .overlay {
                    if isLoadingRaw { ProgressView() }
                }
            }
        }
    }

    // MARK: Actions

    private func loadRaw() async {
        guard let volume = solo else {
            rawJSON = ""
            return
        }
        isLoadingRaw = true
        let inspection = await model.inspect(name: volume.id)
        rawJSON = JSONPrettyPrinter.prettyPrint(inspection.rawJSON)
        isLoadingRaw = false
    }
}
