//
//  NetworkInspectorView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The networks inspector: a Summary tab (mode, plugin, subnet/gateway/ipv6 as copyable
//  fields, internal/builtin flags, and the connected containers with a prominent count) plus
//  a Raw JSON tab fed by `network inspect`. The raw payload is always shown even when
//  decoding drifts, and is copyable. AppKit (NSPasteboard) is permitted in the UI layer.

import AppKit
import CapsuleDomain
import SwiftUI

struct NetworkInspectorView: View {
    let model: NetworkBrowserModel

    @State private var rawJSON = ""
    @State private var isLoadingRaw = false

    init(model: NetworkBrowserModel) {
        self.model = model
    }

    /// The single selected network, when exactly one row is selected.
    private var solo: Network? {
        guard model.selection.count == 1, let id = model.selection.first else { return nil }
        return model.selectedNetworks.first { $0.id == id }
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
                "No Selection", systemImage: "network",
                description: Text("Select a network to see its details."))
        } else if let network = solo {
            Form {
                Section("Network") {
                    LabeledContent("Name", value: network.name)
                    LabeledContent("Mode", value: network.mode ?? "—")
                    LabeledContent("Plugin", value: network.plugin ?? "—")
                    copyableField("IPv4 Subnet", value: network.ipv4Subnet)
                    copyableField("Gateway", value: network.ipv4Gateway)
                    copyableField("IPv6 Subnet", value: network.ipv6Subnet)
                    if network.internal {
                        LabeledContent("Connectivity", value: "Internal (no external access)")
                    }
                    if network.isBuiltin {
                        LabeledContent("State") {
                            Label("Builtin (protected)", systemImage: "lock.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let created = network.createdAt {
                        LabeledContent("Created") { Text(created, format: .dateTime) }
                    }
                }

                Section("Connected Containers (\(network.connectedContainers.count))") {
                    if network.connectedContainers.isEmpty {
                        Text("No connected containers.").foregroundStyle(.secondary)
                    } else {
                        ForEach(network.connectedContainers, id: \.self) { name in
                            Text(name)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "\(model.selection.count) Networks Selected", systemImage: "network",
                description: Text("Select a single network to see its details."))
        }
    }

    /// A labeled value with a copy button when present; an em dash when absent.
    @ViewBuilder
    private func copyableField(_ label: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label) {
                HStack(spacing: 6) {
                    Text(value).font(.system(.body, design: .monospaced))
                    Button {
                        Pasteboard.copy(value)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy \(label) (\(value))")
                }
            }
        } else {
            LabeledContent(label, value: "—")
        }
    }

    // MARK: Raw JSON

    @ViewBuilder
    private var rawTab: some View {
        if solo == nil {
            ContentUnavailableView(
                "No Selection", systemImage: "curlybraces",
                description: Text("Select a single network to inspect its raw JSON."))
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
        guard let network = solo else {
            rawJSON = ""
            return
        }
        isLoadingRaw = true
        let inspection = await model.inspect(name: network.name)
        rawJSON = JSONPrettyPrinter.prettyPrint(inspection.rawJSON)
        isLoadingRaw = false
    }
}
