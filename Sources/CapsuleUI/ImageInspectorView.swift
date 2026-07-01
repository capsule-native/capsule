//
//  ImageInspectorView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The images inspector: a friendly Summary tab (repository, tag, full digest with a copy
//  button, size, created) plus a Raw JSON tab fed by `image inspect`. The raw payload is
//  always shown even when decoding drifts, and is copyable. Digest-centric copy actions
//  live here so a user is never ambiguous about which image they acted on. AppKit
//  (NSPasteboard) is permitted in the UI layer.

import AppKit
import CapsuleDomain
import SwiftUI

struct ImageInspectorView: View {
    let model: ImageBrowserModel

    @State private var rawJSON = ""
    @State private var isLoadingRaw = false

    init(model: ImageBrowserModel) {
        self.model = model
    }

    /// The single selected image, when exactly one row is selected.
    private var solo: CapsuleDomain.Image? {
        guard model.selection.count == 1, let id = model.selection.first else { return nil }
        return model.selectedImages.first { $0.id == id }
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
                "No Selection", systemImage: "square.stack.3d.up",
                description: Text("Select an image to see its details."))
        } else if let image = solo {
            Form {
                Section("Image") {
                    LabeledContent("Repository", value: image.repository)
                    LabeledContent("Tag", value: image.tag ?? "—")
                    LabeledContent("Digest") {
                        HStack(spacing: 6) {
                            Text(image.shortDigest)
                                .font(.system(.body, design: .monospaced))
                            Button {
                                Pasteboard.copy(image.digest)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Copy digest", bundle: .module))
                            .help(Text("Copy full digest (\(image.digest))", bundle: .module))
                        }
                    }
                    LabeledContent("Size") {
                        Text(image.sizeBytes, format: .byteCount(style: .file))
                    }
                    if let created = image.createdAt {
                        LabeledContent("Created") { Text(created, format: .dateTime) }
                    }
                    if image.isDangling {
                        LabeledContent("State", value: "Dangling (untagged)")
                    }
                }

                Section {
                    Button {
                        Pasteboard.copy(image.digest)
                    } label: {
                        Label("Copy Digest", systemImage: "number")
                    }
                    Button {
                        Pasteboard.copy(image.reference)
                    } label: {
                        Label("Copy Reference", systemImage: "doc.on.doc")
                    }
                    .disabled(image.isDangling)
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "\(model.selection.count) Images Selected",
                systemImage: "square.stack.3d.up",
                description: Text("Select a single image to see its details."))
        }
    }

    // MARK: Raw JSON

    @ViewBuilder
    private var rawTab: some View {
        if solo == nil {
            ContentUnavailableView(
                "No Selection", systemImage: "curlybraces",
                description: Text("Select a single image to inspect its raw JSON."))
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
                    if isLoadingRaw {
                        ProgressView()
                            .accessibilityLabel(Text("Loading", bundle: .module))
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func loadRaw() async {
        guard let image = solo else {
            rawJSON = ""
            return
        }
        isLoadingRaw = true
        let inspection = await model.inspect(reference: image.id)
        rawJSON = JSONPrettyPrinter.prettyPrint(inspection.rawJSON)
        isLoadingRaw = false
    }
}
