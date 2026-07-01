//
//  NetworkListView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The networks content column: a Table backed by NetworkBrowserModel with search, a context
//  menu (single-row Copy/Delete), and a toolbar (Create…, Clean Up = prune, Refresh). Builtin
//  networks show a lock and a disabled Delete and are excluded from bulk delete. Destructive
//  actions always confirm via the generic ConfirmationSheet.

import AppKit
import CapsuleDomain
import SwiftUI

struct NetworkListView: View {
    @Bindable var model: NetworkBrowserModel
    let actions: NetworkActionsModel

    @State private var activeSheet: NetworkSheet?

    init(model: NetworkBrowserModel, actions: NetworkActionsModel) {
        self.model = model
        self.actions = actions
    }

    var body: some View {
        content
            .toolbar { toolbarContent }
            .task { await model.refresh() }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .create:
                    CreateNetworkSheet(
                        actions: actions, existingNetworks: model.allNetworks,
                        onClose: { activeSheet = nil })
                case .prune:
                    NetworkPruneSheet(actions: actions, onClose: { activeSheet = nil })
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

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading:
            ProgressView("Loading networks…")
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
                    Label("No networks yet", systemImage: "network")
                } description: {
                    Text("Networks you create will appear here.")
                }
            } else {
                table
            }
        }
    }

    private var table: some View {
        Table(model.rows, selection: $model.selection) {
            TableColumn(Text("Protected", bundle: .module)) { network in
                if network.isBuiltin {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .help("Builtin network (protected)")
                        .accessibilityLabel(Text("Built-in network", bundle: .module))
                }
            }
            .width(18)

            TableColumn("Name") { Text($0.name) }
            TableColumn("Subnet") { network in
                Text(network.ipv4Subnet ?? "—")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            TableColumn("Connections") { network in
                Text("\(network.connectedContainers.count)")
                    .foregroundStyle(.secondary)
            }
            TableColumn("Created") { network in
                if let created = network.createdAt {
                    Text(created, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu(forSelectionType: Network.ID.self) { ids in
            rowMenu(for: ids)
        }
        .onDeleteCommand { requestDelete(ids: model.selection) }
        .overlay {
            if model.noMatches { ContentUnavailableView.search }
        }
    }

    @ViewBuilder
    private func rowMenu(for ids: Set<Network.ID>) -> some View {
        let targets = networks(for: ids)
        let deletable = targets.filter { !$0.isBuiltin }
        if let single = targets.first, targets.count == 1 {
            Button("Inspect") { model.selection = [single.id] }
            Divider()
            Button("Copy Name") { Pasteboard.copy(single.name) }
            if let subnet = single.ipv4Subnet {
                Button("Copy Subnet") { Pasteboard.copy(subnet) }
            }
            Divider()
        }
        Button("Delete…", role: .destructive) { requestDelete(ids: ids) }
            .disabled(deletable.isEmpty)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                activeSheet = .create
            } label: {
                Label("Create", systemImage: "plus")
            }
            .help("Create a network")

            Button {
                activeSheet = .prune
            } label: {
                Label("Clean Up", systemImage: "trash")
            }
            .help("Remove networks with no connections")

            Button {
                Task { await model.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Reload networks")
        }
    }

    // MARK: - Destructive actions

    /// Builtin networks are filtered out (protected). A single non-builtin target uses the
    /// singular domain builder (which checks isBuiltin and names connected containers); a
    /// multi-select uses the plural builder which aggregates connected containers for all
    /// selected networks.
    private func requestDelete(ids: Set<Network.ID>) {
        let targets = networks(for: ids).filter { !$0.isBuiltin }
        guard !targets.isEmpty else { return }
        if targets.count == 1 {
            let network = targets[0]
            if let request = ConfirmationRequest.deleteNetwork(
                name: network.name, isBuiltin: network.isBuiltin,
                attachments: attachmentIndex())
            {
                activeSheet = .confirm(request)
            }
        } else {
            let names = targets.map(\.name)
            if let request = ConfirmationRequest.deleteNetwork(
                names: names, attachments: attachmentIndex())
            {
                activeSheet = .confirm(request)
            }
        }
    }

    private func performConfirmed(_ request: ConfirmationRequest) {
        switch request.kind {
        case .deleteNetwork:
            let names = request.targetIDs.filter { name in
                !model.allNetworks.contains { $0.name == name && $0.isBuiltin }
            }
            guard !names.isEmpty else { return }
            Task {
                if names.count == 1 {
                    await actions.delete(name: names[0])
                } else {
                    await actions.deleteAll(names: names)
                }
            }
        default:
            break  // other kinds are not raised by the networks surface
        }
    }

    /// Builds an attachment index from the already-stamped browser rows, so the delete
    /// confirmation can name connected containers without another backend round-trip.
    private func attachmentIndex() -> AttachmentIndex {
        var networks: [String: [String]] = [:]
        for network in model.allNetworks {
            networks[network.name] = network.connectedContainers
        }
        return AttachmentIndex(volumes: [:], networks: networks)
    }

    private func networks(for ids: Set<Network.ID>) -> [Network] {
        model.allNetworks.filter { ids.contains($0.id) }
    }
}

/// Which network sheet is presented.
enum NetworkSheet: Identifiable {
    case create
    case prune
    case confirm(ConfirmationRequest)

    var id: String {
        switch self {
        case .create: return "create"
        case .prune: return "prune"
        case let .confirm(request): return "confirm-\(request.id)"
        }
    }
}
