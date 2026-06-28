//
//  ImageListView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The images content column: a Table backed by ImageBrowserModel (read surface) with
//  search, sort, and a dangling filter, plus digest-centric copy actions. Image operations
//  (pull/push/save/load/tag/delete/prune) are layered on by ImageActionsModel + TaskCenter
//  in later milestone phases.

import CapsuleDomain
import SwiftUI

/// Within this file `Image` is the domain model, not `SwiftUI.Image` (this view never uses
/// the latter).
private typealias Image = CapsuleDomain.Image

struct ImageListView: View {
    @Bindable var model: ImageBrowserModel
    let actions: ImageActionsModel

    @State private var activeSheet: ImageSheet?

    init(model: ImageBrowserModel, actions: ImageActionsModel) {
        self.model = model
        self.actions = actions
    }

    var body: some View {
        content
            .searchable(text: $model.searchText, prompt: "Search images")
            .toolbar { toolbarContent }
            .task { await model.refresh() }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case let .tag(reference, digest):
                    TagImageSheet(
                        sourceReference: reference, sourceDigest: digest,
                        onTag: { target in
                            activeSheet = nil
                            Task { await actions.tag(source: reference, target: target) }
                        },
                        onCancel: { activeSheet = nil })
                case let .confirm(request):
                    ConfirmationSheet(
                        request: request,
                        onConfirm: { req in
                            activeSheet = nil
                            performConfirmed(req)
                        }, onCancel: { activeSheet = nil })
                case .prune:
                    ImagePruneSheet(actions: actions, onClose: { activeSheet = nil })
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading:
            ProgressView("Loading images…")
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
                    Label("No images yet", systemImage: "square.stack.3d.up")
                } description: {
                    Text("Images you pull or build will appear here.")
                }
            } else {
                table
            }
        }
    }

    private var table: some View {
        Table(model.rows, selection: $model.selection) {
            TableColumn("") { image in
                if image.isDangling {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                        .help("Dangling (untagged) image")
                } else {
                    Circle().fill(.secondary).frame(width: 8, height: 8).opacity(0.4)
                }
            }
            .width(18)

            TableColumn("Repository") { Text($0.repository) }
            TableColumn("Tag") { image in
                Text(image.tag ?? "—").foregroundStyle(.secondary)
            }
            TableColumn("Digest") { image in
                Text(image.shortDigest)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            TableColumn("Size") { image in
                Text(image.sizeBytes, format: .byteCount(style: .file))
                    .foregroundStyle(.secondary)
            }
            TableColumn("Created") { image in
                if let created = image.createdAt {
                    Text(created, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu(forSelectionType: Image.ID.self) { ids in
            rowMenu(for: ids)
        }
        .onDeleteCommand { requestDelete(ids: model.selection) }
        .overlay {
            if model.noMatches { ContentUnavailableView.search }
        }
    }

    @ViewBuilder
    private func rowMenu(for ids: Set<Image.ID>) -> some View {
        let targets = images(for: ids)
        if let single = targets.first, targets.count == 1 {
            Button("Copy Digest") { Pasteboard.copy(single.digest) }
            Button("Copy Reference") { Pasteboard.copy(single.reference) }
                .disabled(single.isDangling)
            Divider()
            Button("Tag…") {
                activeSheet = .tag(reference: single.id, digest: single.digest)
            }
        }
        Divider()
        Button("Delete…", role: .destructive) { requestDelete(ids: ids) }
            .disabled(targets.isEmpty)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Sort", selection: $model.sort) {
                ForEach(ImageSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.segmented)
            .help("Sort images")
        }

        ToolbarItemGroup {
            Toggle(isOn: $model.showDanglingOnly) {
                Label("Dangling only", systemImage: "questionmark.diamond")
            }
            .help("Show only untagged (dangling) images")

            Button {
                activeSheet = .prune
            } label: {
                Label("Clean Up", systemImage: "trash")
            }
            .help("Remove dangling or unused images")
        }
    }

    // MARK: - Destructive actions

    /// Deleting an image always confirms; the delete itself surfaces a dependency conflict
    /// (image still referenced by a container) as a notice.
    private func requestDelete(ids: Set<Image.ID>) {
        let targets = images(for: ids)
        guard !targets.isEmpty else { return }
        if let request = ConfirmationRequest.deleteImage(ids: targets.map(\.id)) {
            activeSheet = .confirm(request)
        }
    }

    private func performConfirmed(_ request: ConfirmationRequest) {
        switch request.kind {
        case .deleteImage:
            Task { await actions.deleteAll(references: request.targetIDs) }
        default:
            break  // other kinds are not raised by the images surface
        }
    }

    private func images(for ids: Set<Image.ID>) -> [Image] {
        model.allImages.filter { ids.contains($0.id) }
    }
}

/// Which image sheet is presented.
enum ImageSheet: Identifiable {
    case tag(reference: String, digest: String)
    case confirm(ConfirmationRequest)
    case prune

    var id: String {
        switch self {
        case let .tag(reference, _): return "tag-\(reference)"
        case let .confirm(request): return "confirm-\(request.id)"
        case .prune: return "prune"
        }
    }
}
