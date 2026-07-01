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

import AppKit
import CapsuleDomain
import SwiftUI

/// Within this file `Image` is the domain model, not `SwiftUI.Image` (this view never uses
/// the latter).
private typealias Image = CapsuleDomain.Image

struct ImageListView: View {
    @Bindable var model: ImageBrowserModel
    let actions: ImageActionsModel
    let registrySearchModel: RegistrySearchModel
    @Bindable var runModel: RunModel
    @Bindable var buildModel: BuildModel

    @State private var activeSheet: ImageSheet?

    init(
        model: ImageBrowserModel, actions: ImageActionsModel,
        registrySearchModel: RegistrySearchModel, runModel: RunModel,
        buildModel: BuildModel
    ) {
        self.model = model
        self.actions = actions
        self.registrySearchModel = registrySearchModel
        self.runModel = runModel
        self.buildModel = buildModel
    }

    var body: some View {
        content
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
                        onCancel: { activeSheet = nil },
                        invocationFor: { target in
                            actions.tagInvocation(source: reference, target: target)
                        })
                case let .pull(reference):
                    PullImageSheet(
                        initialReference: reference,
                        searchModel: registrySearchModel,
                        onPull: { ref, plat in actions.pull(reference: ref, platform: plat) },
                        onRetry: { actions.retryTask($0) },
                        onClose: { activeSheet = nil },
                        invocationFor: { ref, plat in
                            actions.pullInvocation(reference: ref, platform: plat)
                        })
                case let .push(reference, digest):
                    PushImageSheet(
                        initialReference: reference, initialDigest: digest,
                        onPush: { ref, plat in actions.push(reference: ref, platform: plat) },
                        onRetry: { actions.retryTask($0) },
                        onClose: { activeSheet = nil },
                        invocationFor: { ref, plat in
                            actions.pushInvocation(reference: ref, platform: plat)
                        })
                case .load:
                    LoadImageSheet(
                        onLoad: { url in actions.load(from: url) },
                        onRetry: { actions.retryTask($0) },
                        onClose: { activeSheet = nil },
                        invocationFor: { url in actions.loadInvocation(from: url) })
                case let .confirm(request):
                    ConfirmationSheet(
                        request: request,
                        onConfirm: { req in
                            activeSheet = nil
                            performConfirmed(req)
                        }, onCancel: { activeSheet = nil })
                case .prune:
                    ImagePruneSheet(actions: actions, onClose: { activeSheet = nil })
                case let .run(image):
                    QuickRunSheet(
                        model: runModel,
                        onResolveImage: { ref in activeSheet = .pull(reference: ref) },
                        onClose: { activeSheet = nil }
                    )
                    .onAppear { runModel.reset(image: image) }
                case .build:
                    BuildSheet(model: buildModel, onClose: { activeSheet = nil })
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
            TableColumn(Text("Status", bundle: .module)) { image in
                if image.isDangling {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                        .help(Text("Dangling (untagged) image", bundle: .module))
                        .accessibilityLabel(Text("Dangling image", bundle: .module))
                } else {
                    Circle().fill(.secondary).frame(width: 8, height: 8).opacity(0.4)
                        .accessibilityHidden(true)
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
            Button("Run Image…") { activeSheet = .run(image: single.reference) }
                .disabled(single.isDangling)
            Divider()
            Button("Copy Digest") { Pasteboard.copy(single.digest) }
            Button("Copy Reference") { Pasteboard.copy(single.reference) }
                .disabled(single.isDangling)
            Divider()
            Button("Tag…") {
                activeSheet = .tag(reference: single.id, digest: single.digest)
            }
            Button("Push…") {
                activeSheet = .push(reference: single.reference, digest: single.digest)
            }
            .disabled(single.isDangling)
        }
        Button("Save…") { requestSave(targets) }
            .disabled(targets.isEmpty)
        Divider()
        Button("Delete…", role: .destructive) { requestDelete(ids: ids) }
            .disabled(targets.isEmpty)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                activeSheet = .run(image: selectedReference ?? "")
            } label: {
                Label("Run", systemImage: "play.rectangle")
            }
            .help("Run a container from an image")

            Button {
                activeSheet = .build
            } label: {
                Label("Build", systemImage: "hammer")
            }
            .help("Build an image from a Dockerfile")

            Button {
                activeSheet = .pull(reference: "")
            } label: {
                Label("Pull", systemImage: "arrow.down.circle")
            }
            .help("Pull an image from a registry")

            Button {
                activeSheet = .load
            } label: {
                Label("Load", systemImage: "square.and.arrow.up")
            }
            .help("Load images from a tar archive")
        }

        ToolbarItem(placement: .principal) {
            Picker("Sort", selection: $model.sort) {
                ForEach(ImageSort.allCases) { sort in
                    Text(sort.localizedTitle).tag(sort)
                }
            }
            .pickerStyle(.segmented)
            .help("Sort images")
        }

        ToolbarItemGroup(placement: .navigation) {
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

    /// Saves the selected image(s) to a single tar archive via a Save panel.
    private func requestSave(_ targets: [Image]) {
        guard !targets.isEmpty else { return }
        let references = targets.map(\.id)
        let panel = NSSavePanel()
        let suggested = targets.count == 1 ? targets[0].repository : "images"
        panel.nameFieldStringValue =
            "\((suggested as NSString).lastPathComponent).tar"
        panel.canCreateDirectories = true
        panel.title = "Save Image\(targets.count == 1 ? "" : "s")"
        if panel.runModal() == .OK, let url = panel.url {
            actions.save(references: references, to: url, platform: nil)
        }
    }

    private func images(for ids: Set<Image.ID>) -> [Image] {
        model.allImages.filter { ids.contains($0.id) }
    }

    /// The reference of the single selected, non-dangling image (prefills the Run sheet).
    private var selectedReference: String? {
        let targets = images(for: model.selection)
        guard targets.count == 1, let single = targets.first, !single.isDangling else { return nil }
        return single.reference
    }
}

/// Which image sheet is presented.
enum ImageSheet: Identifiable {
    case tag(reference: String, digest: String)
    case pull(reference: String)
    case push(reference: String, digest: String)
    case load
    case confirm(ConfirmationRequest)
    case prune
    case run(image: String)
    case build

    var id: String {
        switch self {
        case let .tag(reference, _): return "tag-\(reference)"
        case .pull: return "pull"
        case let .push(reference, _): return "push-\(reference)"  // id stays stable
        case .load: return "load"
        case let .confirm(request): return "confirm-\(request.id)"
        case .prune: return "prune"
        case let .run(image): return "run-\(image)"
        case .build: return "build"
        }
    }
}
