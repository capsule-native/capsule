//
//  ContainerListView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The containers content column: a Table backed by ContainerBrowserModel (read surface)
//  plus non-destructive lifecycle actions (start/stop) driven by ContainerLifecycleModel
//  and metric chips from ContainerStatsModel. Filtering/scope logic lives in the browser
//  model (unit-tested there). Destructive actions arrive in Milestone 5C.

import CapsuleDomain
import SwiftUI

struct ContainerListView: View {
    @Bindable var model: ContainerBrowserModel
    let lifecycle: ContainerLifecycleModel
    let stats: ContainerStatsModel

    @State private var showingSaveScope = false
    @State private var newScopeName = ""
    @State private var activeSheet: LifecycleSheet?

    init(
        model: ContainerBrowserModel,
        lifecycle: ContainerLifecycleModel,
        stats: ContainerStatsModel
    ) {
        self.model = model
        self.lifecycle = lifecycle
        self.stats = stats
    }

    var body: some View {
        content
            .searchable(text: $model.searchText, prompt: "Search containers")
            .toolbar { toolbarContent }
            .task {
                model.loadScopes()
                await model.refresh()
                await stats.snapshot(ids: runningIDs)
            }
            .alert("Save Scope", isPresented: $showingSaveScope) {
                TextField("Scope name", text: $newScopeName)
                Button("Save") {
                    let name = newScopeName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { model.saveCurrentScope(name: name) }
                    newScopeName = ""
                }
                Button("Cancel", role: .cancel) { newScopeName = "" }
            } message: {
                Text("Saves the current filter and search as a reusable scope.")
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case let .startAttach(id, name):
                    StartAttachSheet(
                        containerName: name, terminalAvailable: lifecycle.isTerminalAvailable,
                        onStart: { attach in
                            activeSheet = nil
                            Task { _ = await lifecycle.start(id: id, attach: attach) }
                        }, onCancel: { activeSheet = nil })
                case let .stopOptions(id, name):
                    StopOptionsSheet(
                        containerName: name,
                        onStop: { timeout, signal in
                            activeSheet = nil
                            Task {
                                _ = await lifecycle.stop(id: id, timeout: timeout, signal: signal)
                            }
                        }, onCancel: { activeSheet = nil })
                }
            }
    }

    private var runningIDs: [String] {
        model.allContainers.filter { $0.state == .running }.map(\.id)
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading:
            ProgressView("Loading containers…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let detail):
            ContentUnavailableView {
                Label(detail.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(detail.explanation)
            }
        case .loaded:
            if model.isEmptyButHealthy {
                ContentUnavailableView {
                    Label("No containers yet", systemImage: "shippingbox")
                } description: {
                    Text("Containers you create will appear here.")
                }
            } else {
                table
            }
        }
    }

    private var table: some View {
        Table(model.rows, selection: $model.selection) {
            TableColumn("") { container in
                if lifecycle.busy.contains(container.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Circle()
                        .fill(CapsuleColors.containerStateColor(container.state))
                        .frame(width: 8, height: 8)
                        .help(container.state.rawValue.capitalized)
                }
            }
            .width(18)

            TableColumn("Name") { Text($0.name) }
            TableColumn("Image") { Text($0.image).foregroundStyle(.secondary) }
            TableColumn("CPU / Mem") { container in
                StatChips(metrics: stats.metrics[container.id])
            }
            TableColumn("IP") { container in
                Text(container.ip ?? "—").foregroundStyle(.secondary)
            }
            TableColumn("Created") { container in
                if let created = container.createdAt {
                    Text(created, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu(forSelectionType: Container.ID.self) { ids in
            rowMenu(for: ids)
        }
        .overlay {
            if model.noMatches { ContentUnavailableView.search }
        }
    }

    // MARK: - Lifecycle menus / actions

    @ViewBuilder
    private func rowMenu(for ids: Set<Container.ID>) -> some View {
        let targets = containers(for: ids)
        let startable = targets.filter { $0.state != .running }
        let stoppable = targets.filter { $0.state == .running }

        Button("Start") { Task { await lifecycle.startAll(ids: startable.map(\.id)) } }
            .disabled(startable.isEmpty)
        if let single = startable.first, startable.count == 1 {
            Button("Start and Attach…") {
                activeSheet = .startAttach(id: single.id, name: single.name)
            }
        }
        Divider()
        Button("Stop") { Task { await stopAll(stoppable.map(\.id)) } }
            .disabled(stoppable.isEmpty)
        if let single = stoppable.first, stoppable.count == 1 {
            Button("Stop…") {
                activeSheet = .stopOptions(id: single.id, name: single.name)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                Task { await lifecycle.startAll(ids: selectedStartableIDs) }
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(selectedStartableIDs.isEmpty)
            .help("Start the selected containers")

            Button {
                Task { await stopAll(selectedStoppableIDs) }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(selectedStoppableIDs.isEmpty)
            .help("Stop the selected containers")
        }

        ToolbarItem(placement: .principal) {
            Picker("Filter", selection: $model.stateFilter) {
                ForEach(ContainerStateFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .help("Filter containers by state")
        }

        ToolbarItem {
            Menu {
                ForEach(ContainerScope.builtIns) { scope in
                    Button(scope.name) { model.activate(scope) }
                }
                if !model.savedScopes.isEmpty {
                    Divider()
                    ForEach(model.savedScopes) { scope in
                        Button(scope.name) { model.activate(scope) }
                    }
                    Divider()
                    Menu("Remove Scope") {
                        ForEach(model.savedScopes) { scope in
                            Button(scope.name, role: .destructive) { model.removeScope(scope) }
                        }
                    }
                }
                Divider()
                Button("Save Current as Scope…") {
                    newScopeName = ""
                    showingSaveScope = true
                }
            } label: {
                Label("Scopes", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Saved scopes and views")
        }
    }

    private func stopAll(_ ids: [String]) async {
        for id in ids { _ = await lifecycle.stop(id: id) }
        await stats.snapshot(ids: runningIDs)
    }

    private func containers(for ids: Set<Container.ID>) -> [Container] {
        model.allContainers.filter { ids.contains($0.id) }
    }

    private var selectedStartableIDs: [String] {
        containers(for: model.selection).filter { $0.state != .running }.map(\.id)
    }

    private var selectedStoppableIDs: [String] {
        containers(for: model.selection).filter { $0.state == .running }.map(\.id)
    }
}

/// Which lifecycle sheet is presented (single-target only).
enum LifecycleSheet: Identifiable {
    case startAttach(id: String, name: String)
    case stopOptions(id: String, name: String)

    var id: String {
        switch self {
        case let .startAttach(id, _): return "start-\(id)"
        case let .stopOptions(id, _): return "stop-\(id)"
        }
    }
}
