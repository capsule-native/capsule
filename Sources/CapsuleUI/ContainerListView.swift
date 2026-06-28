//
//  ContainerListView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The containers content column: a Table backed by ContainerBrowserModel. Filtering and
//  scope logic live in the model (and are unit-tested there); this view is the thin
//  presentation + selection surface. Lifecycle actions arrive in Milestone 5B.

import CapsuleDomain
import SwiftUI

struct ContainerListView: View {
    @Bindable var model: ContainerBrowserModel

    @State private var showingSaveScope = false
    @State private var newScopeName = ""

    init(model: ContainerBrowserModel) {
        self.model = model
    }

    var body: some View {
        content
            .searchable(text: $model.searchText, prompt: "Search containers")
            .toolbar { toolbarContent }
            .task {
                model.loadScopes()
                await model.refresh()
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
                Circle()
                    .fill(CapsuleColors.containerStateColor(container.state))
                    .frame(width: 8, height: 8)
                    .help(container.state.rawValue.capitalized)
            }
            .width(16)

            TableColumn("Name") { Text($0.name) }
            TableColumn("Image") { Text($0.image).foregroundStyle(.secondary) }
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
        .overlay {
            if model.noMatches {
                ContentUnavailableView.search
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                            Button(scope.name, role: .destructive) {
                                model.removeScope(scope)
                            }
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
}
