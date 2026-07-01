//
//  VolumeListView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The volumes content column: a Table backed by VolumeBrowserModel (read surface) with a
//  context menu (Inspect, Delete…) and a toolbar (Create…, Clean Up, Refresh). Delete
//  confirmations embed the mounting-container warning from the per-row attachment list.

import CapsuleDomain
import SwiftUI

struct VolumeListView: View {
    @Bindable var model: VolumeBrowserModel
    let actions: VolumeActionsModel

    @State private var activeSheet: VolumeSheet?

    init(model: VolumeBrowserModel, actions: VolumeActionsModel) {
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
                    CreateVolumeSheet(actions: actions, onClose: { activeSheet = nil })
                case .prune:
                    VolumePruneSheet(actions: actions, onClose: { activeSheet = nil })
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
            ProgressView("Loading volumes…")
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
                    Label("No volumes yet", systemImage: "externaldrive")
                } description: {
                    Text("Volumes you create will appear here.")
                }
            } else {
                table
            }
        }
    }

    private var table: some View {
        Table(model.rows, selection: $model.selection) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("Size") { volume in
                if let bytes = volume.sizeBytes {
                    Text(bytes, format: .byteCount(style: .file)).foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            TableColumn("Attached") { volume in
                if volume.attachedContainers.isEmpty {
                    Text("—").foregroundStyle(.secondary)
                } else {
                    Text("\(volume.attachedContainers.count)")
                        .help(volume.attachedContainers.joined(separator: ", "))
                }
            }
            TableColumn("Created") { volume in
                if let created = volume.createdAt {
                    Text(created, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu(forSelectionType: Volume.ID.self) { ids in
            rowMenu(for: ids)
        }
        .onDeleteCommand { requestDelete(ids: model.selection) }
        .overlay {
            if model.noMatches { ContentUnavailableView.search }
        }
    }

    @ViewBuilder
    private func rowMenu(for ids: Set<Volume.ID>) -> some View {
        let targets = volumes(for: ids)
        if let single = targets.first, targets.count == 1 {
            Button("Inspect") { model.selection = [single.id] }
            Divider()
        }
        Button("Delete…", role: .destructive) { requestDelete(ids: ids) }
            .disabled(targets.isEmpty)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                activeSheet = .create
            } label: {
                Label("Create", systemImage: "plus")
            }
            .help("Create a volume")

            Button {
                activeSheet = .prune
            } label: {
                Label("Clean Up", systemImage: "trash")
            }
            .help("Remove unused volumes")

            Button {
                Task { await model.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Reload the volume list")
        }
    }

    // MARK: - Destructive actions

    /// Deleting a volume always confirms; the confirmation embeds the data-loss warning and,
    /// when mounted, the mounting-container names.
    private func requestDelete(ids: Set<Volume.ID>) {
        let targets = volumes(for: ids)
        guard !targets.isEmpty else { return }
        if let request = ConfirmationRequest.deleteVolume(
            names: targets.map(\.id), attachments: attachmentIndex())
        {
            activeSheet = .confirm(request)
        }
    }

    private func performConfirmed(_ request: ConfirmationRequest) {
        switch request.kind {
        case .deleteVolume:
            Task { await actions.deleteAll(names: request.targetIDs) }
        default:
            break  // other kinds are not raised by the volumes surface
        }
    }

    /// Rebuilds the attachment index from the already-stamped rows (no extra backend call).
    private func attachmentIndex() -> AttachmentIndex {
        var volumes: [String: [String]] = [:]
        for volume in model.allVolumes where !volume.attachedContainers.isEmpty {
            volumes[volume.name] = volume.attachedContainers
        }
        return AttachmentIndex(volumes: volumes, networks: [:])
    }

    private func volumes(for ids: Set<Volume.ID>) -> [Volume] {
        model.allVolumes.filter { ids.contains($0.id) }
    }
}

/// Which volume sheet is presented.
enum VolumeSheet: Identifiable {
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
