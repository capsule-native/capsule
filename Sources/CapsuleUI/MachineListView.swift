//
//  MachineListView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The machines content column: a Table backed by MachineBrowserModel with search, a context
//  menu (Open Shell / Inspect / View Logs / Settings / Make Default / Stop / Delete…), and a
//  toolbar (Create…, Refresh). Destructive actions always confirm via ConfirmationSheet.

import CapsuleDomain
import SwiftUI

struct MachineListView: View {
    @Bindable var model: MachineBrowserModel
    let actions: MachineActionsModel

    @State private var activeSheet: MachineSheet?

    init(model: MachineBrowserModel, actions: MachineActionsModel) {
        self.model = model
        self.actions = actions
    }

    var body: some View {
        content
            .searchable(text: $model.searchText, prompt: "Search machines")
            .toolbar { toolbarContent }
            .task { await model.refresh() }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .create:
                    // Placeholder — replaced by CreateMachineSheet in Task E1
                    Text("Create machine — coming soon")
                        .padding()
                case let .settings(name):
                    // Placeholder — replaced by MachineSettingsSheet in Task F1
                    Text("Settings for \(name)")
                        .padding()
                case let .logs(name):
                    // Placeholder — replaced by MachineLogsSheet in Task G1
                    Text("Logs for \(name)")
                        .padding()
                case let .confirm(request):
                    ConfirmationSheet(
                        request: request,
                        onConfirm: { req in
                            activeSheet = nil
                            performConfirmed(req)
                        }, onCancel: { activeSheet = nil })
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading:
            ProgressView("Loading machines…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .unavailable(detail):
            ContentUnavailableView {
                Label(detail.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(detail.explanation)
            }
        case .loaded:
            if model.isEmptyButHealthy {
                ContentUnavailableView {
                    Label("No machines yet", systemImage: "desktopcomputer")
                } description: {
                    Text("Machines you create will appear here.")
                }
            } else {
                table
            }
        }
    }

    // MARK: - Table

    private var table: some View {
        Table(model.rows, selection: $model.selection) {
            TableColumn("") { machine in
                if machine.isDefault {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .help("Default machine")
                }
            }
            .width(18)

            TableColumn("Name") { Text($0.name) }

            TableColumn("State") { machine in
                Label(machine.state.label, systemImage: machine.state.symbolName)
                    .foregroundStyle(.secondary)
            }

            TableColumn("CPUs") { machine in
                Text(machine.cpus.map(String.init) ?? "—")
                    .foregroundStyle(.secondary)
            }

            TableColumn("Memory") { machine in
                Text(machine.memory ?? "—")
                    .foregroundStyle(.secondary)
            }

            TableColumn("IP") { machine in
                Text(machine.ipAddress ?? "—")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            TableColumn("Created") { machine in
                if let created = machine.createdAt {
                    Text(created, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu(forSelectionType: Machine.ID.self) { ids in
            rowMenu(for: ids)
        }
        .overlay {
            if model.noMatches { ContentUnavailableView.search }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func rowMenu(for ids: Set<Machine.ID>) -> some View {
        let targets = machines(for: ids)
        if let single = targets.first, targets.count == 1 {
            let name = single.name
            Button("Open Shell") { actions.openShell(name: name) }
            Button("Inspect") { model.selection = [single.id] }
            Button("View Logs") { activeSheet = .logs(name) }
            Button("Settings\u{2026}") { activeSheet = .settings(name) }
            Divider()
            Button("Make Default") {
                let prev = model.defaultMachine?.name
                Task { await actions.makeDefault(name, previousDefault: prev) }
            }
            .disabled(single.isDefault)
            Button("Stop") {
                Task { await actions.stop(name) }
            }
            .disabled(single.state != .running)
            Divider()
            Button("Delete\u{2026}", role: .destructive) {
                activeSheet = .confirm(.deleteMachine(name: name))
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                activeSheet = .create
            } label: {
                Label("Create", systemImage: "plus")
            }
            .help("Create a machine")

            Button {
                Task { await model.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Reload machines")
        }
    }

    // MARK: - Confirmation routing

    private func performConfirmed(_ request: ConfirmationRequest) {
        switch request.kind {
        case .deleteMachine:
            guard let name = request.targetIDs.first else { return }
            Task { await actions.delete(name) }
        default:
            break  // other kinds are not raised by the machines surface
        }
    }

    // MARK: - Helpers

    private func machines(for ids: Set<Machine.ID>) -> [Machine] {
        model.allMachines.filter { ids.contains($0.id) }
    }
}

// MARK: - Sheet enum

/// Which machine sheet is currently presented.
enum MachineSheet: Identifiable {
    case create
    case settings(String)
    case logs(String)
    case confirm(ConfirmationRequest)

    var id: String {
        switch self {
        case .create: return "create"
        case let .settings(name): return "settings-\(name)"
        case let .logs(name): return "logs-\(name)"
        case let .confirm(request): return "confirm-\(request.id)"
        }
    }
}
