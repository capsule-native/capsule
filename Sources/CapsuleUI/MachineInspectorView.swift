//
//  MachineInspectorView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The machines inspector: a Summary tab (state, default badge, IP, CPUs, memory, disk,
//  home-mount, created, optional kernel and nested-virtualisation fields, and a prominent
//  restart-required banner when pending settings changes need a reboot) plus a Raw JSON tab
//  fed by `machine inspect`. The raw payload is always shown even when decoding drifts, and
//  is copyable. AppKit (NSPasteboard) is permitted in the UI layer.

import AppKit
import CapsuleDomain
import SwiftUI

struct MachineInspectorView: View {
    let model: MachineBrowserModel
    @Bindable var actions: MachineActionsModel

    @State private var rawJSON = ""
    @State private var isLoadingRaw = false
    @Environment(\.colorSchemeContrast) private var contrast

    init(model: MachineBrowserModel, actions: MachineActionsModel) {
        self.model = model
        self.actions = actions
    }

    /// The single selected machine, when exactly one row is selected.
    private var solo: Machine? {
        guard model.selection.count == 1, let id = model.selection.first else { return nil }
        return model.selectedMachines.first { $0.id == id }
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
                "No Selection", systemImage: "cpu",
                description: Text("Select a machine to see its details."))
        } else if let machine = solo {
            Form {
                // Restart-required banner at the top of the summary
                if actions.restartRequired(machine.name) {
                    restartBanner(for: machine)
                }

                Section("Machine") {
                    LabeledContent("Name", value: machine.name)

                    LabeledContent("State") {
                        Label(machine.state.label, systemImage: machine.state.symbolName)
                    }

                    if machine.isDefault {
                        LabeledContent("Default") {
                            Label("Default", systemImage: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                    }

                    copyableField("IP Address", value: machine.ipAddress)

                    if let cpus = machine.cpus {
                        LabeledContent("CPUs", value: "\(cpus)")
                    } else {
                        LabeledContent("CPUs", value: "—")
                    }

                    LabeledContent("Memory", value: machine.memory ?? "—")
                    LabeledContent("Disk", value: machine.disk ?? "—")
                    LabeledContent("Home Mount", value: machine.homeMount ?? "—")

                    if let created = machine.createdAt {
                        LabeledContent("Created") { Text(created, format: .dateTime) }
                    }

                    if let kernel = machine.kernel {
                        LabeledContent("Kernel", value: kernel)
                    }

                    if let nested = machine.nestedVirtualization {
                        LabeledContent("Nested Virtualization", value: nested ? "Yes" : "No")
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "\(model.selection.count) Machines Selected", systemImage: "cpu",
                description: Text("Select a single machine to see its details."))
        }
    }

    /// Prominent restart-required banner with Restart Now and Dismiss actions.
    @ViewBuilder
    private func restartBanner(for machine: Machine) -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Restart required")
                        .font(.headline)
                    Text("Settings changes take effect after the machine restarts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button("Restart Now") {
                            Task { await actions.restartNow(machine.name) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Button("Dismiss") {
                            actions.clearRestart(machine.name)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.top, 2)
                }

                Spacer()
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(CapsuleColors.softFill(.yellow, contrast: contrast))
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
                    .accessibilityLabel(Text("Copy \(label)", bundle: .module))
                    .help(Text("Copy \(label) (\(value))", bundle: .module))
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
                description: Text("Select a single machine to inspect its raw JSON."))
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
        guard let machine = solo else {
            rawJSON = ""
            return
        }
        isLoadingRaw = true
        let inspection = await model.inspect(id: machine.name)
        rawJSON = JSONPrettyPrinter.prettyPrint(inspection.rawJSON)
        isLoadingRaw = false
    }
}
