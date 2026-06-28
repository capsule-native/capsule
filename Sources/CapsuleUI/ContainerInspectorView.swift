//
//  ContainerInspectorView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The containers inspector: a friendly Summary tab plus a Raw JSON tab fed by
//  `container inspect`. The raw payload is always shown even when decoding drifts, and is
//  copyable. AppKit (NSPasteboard) is permitted in the UI layer.

import AppKit
import CapsuleDomain
import SwiftUI

struct ContainerInspectorView: View {
    let model: ContainerBrowserModel

    @State private var rawJSON = ""
    @State private var isLoadingRaw = false

    init(model: ContainerBrowserModel) {
        self.model = model
    }

    /// The single selected container, when exactly one row is selected.
    private var solo: Container? {
        guard model.selection.count == 1, let id = model.selection.first else { return nil }
        return model.selectedContainers.first { $0.id == id }
    }

    var body: some View {
        TabView {
            summaryTab
                .tabItem { Label("Summary", systemImage: "info.circle") }
            rawTab
                .tabItem { Label("Raw JSON", systemImage: "curlybraces") }
        }
        .task(id: model.selection) {
            await loadRaw()
        }
    }

    // MARK: Summary

    @ViewBuilder
    private var summaryTab: some View {
        if model.selection.isEmpty {
            ContentUnavailableView(
                "No Selection", systemImage: "shippingbox",
                description: Text("Select a container to see its details."))
        } else if let container = solo {
            Form {
                Section("Container") {
                    LabeledContent("Name", value: container.name)
                    LabeledContent("ID", value: container.shortID)
                    LabeledContent("Image", value: container.image)
                    LabeledContent("State") {
                        Label {
                            Text(container.state.rawValue.capitalized)
                        } icon: {
                            Circle()
                                .fill(CapsuleColors.containerStateColor(container.state))
                                .frame(width: 8, height: 8)
                        }
                    }
                    LabeledContent("IP", value: container.ip ?? "—")
                    if let created = container.createdAt {
                        LabeledContent("Created") {
                            Text(created, format: .dateTime)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "\(model.selection.count) Containers Selected",
                systemImage: "square.stack.3d.up",
                description: Text("Select a single container to see its details."))
        }
    }

    // MARK: Raw JSON

    @ViewBuilder
    private var rawTab: some View {
        if solo == nil {
            ContentUnavailableView(
                "No Selection", systemImage: "curlybraces",
                description: Text("Select a single container to inspect its raw JSON."))
        } else {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        copyRaw()
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
        guard let container = solo else {
            rawJSON = ""
            return
        }
        isLoadingRaw = true
        let inspection = await model.inspect(id: container.id)
        rawJSON = JSONPrettyPrinter.prettyPrint(inspection.rawJSON)
        isLoadingRaw = false
    }

    private func copyRaw() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(rawJSON, forType: .string)
    }
}
