//
//  RegistryBrowseView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Browse pane of the Pull Image sheet: a Docker Hub catalog search driven by
//  `RegistrySearchModel` in two stages — repository results, then the selected repository's
//  tags. Picking a tag hands the composed pull reference up via `onPick`; the view owns no
//  network or search state of its own.

import CapsuleDomain
import SwiftUI

struct RegistryBrowseView: View {
    @Bindable var model: RegistrySearchModel
    let onPick: (String) -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        if let repository = model.selectedRepository {
            tagStage(for: repository)
        } else {
            searchStage
        }
    }

    // MARK: - Search stage

    private var searchStage: some View {
        VStack(spacing: 8) {
            TextField(
                "Search", text: $model.searchText,
                prompt: Text("Search Docker Hub…", bundle: .module)
            )
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            .onSubmit { model.searchNow() }
            .accessibilityIdentifier("pull-browse-search-field")

            searchContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { searchFocused = true }
    }

    @ViewBuilder
    private var searchContent: some View {
        switch model.loadState {
        case .idle:
            ContentUnavailableView {
                Label("Search Docker Hub", systemImage: "magnifyingglass")
            } description: {
                Text("Type at least two characters to search for images.", bundle: .module)
            }
        case .loading:
            ProgressView { Text("Searching Docker Hub…", bundle: .module) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .throttled:
            throttledState
        case .unavailable(let detail):
            unavailableState(detail) { model.searchNow() }
        case .loaded:
            if model.repositories.isEmpty {
                ContentUnavailableView {
                    Label("No images found", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different search term.", bundle: .module)
                }
            } else {
                resultsList
            }
        }
    }

    private var resultsList: some View {
        List {
            ForEach(model.repositories) { repository in
                Button {
                    model.selectRepository(repository)
                } label: {
                    RegistryRepositoryRow(repository: repository)
                }
                .buttonStyle(.plain)
            }
            if model.hasMoreRepositories {
                loadMoreRow(isLoading: model.isLoadingMore) { model.loadMoreRepositories() }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("pull-browse-results")
    }

    // MARK: - Tag stage

    private func tagStage(for repository: RegistryRepository) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    model.clearSelection()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back to results", bundle: .module))

                Text(verbatim: repository.name)
                    .font(.headline)
                Spacer()
            }

            tagContent(for: repository)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func tagContent(for repository: RegistryRepository) -> some View {
        switch model.tagState {
        case .idle, .loading:
            ProgressView { Text("Loading tags…", bundle: .module) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .throttled:
            throttledState
        case .unavailable(let detail):
            unavailableState(detail) { model.retryTags() }
        case .loaded:
            if model.tags.isEmpty {
                ContentUnavailableView {
                    Label("No tags found", systemImage: "tag")
                } description: {
                    Text("This repository has no tags to pull.", bundle: .module)
                }
            } else {
                tagList(for: repository)
            }
        }
    }

    private func tagList(for repository: RegistryRepository) -> some View {
        List {
            ForEach(model.tags) { tag in
                Button {
                    onPick(repository.pullReference(tag: tag.name))
                } label: {
                    RegistryTagRow(tag: tag)
                }
                .buttonStyle(.plain)
            }
            if model.hasMoreTags {
                loadMoreRow(isLoading: model.isLoadingMoreTags) { model.loadMoreTags() }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("pull-browse-tags")
    }

    // MARK: - Shared states

    private var throttledState: some View {
        ContentUnavailableView {
            Label("Docker Hub is busy", systemImage: "clock.badge.exclamationmark")
        } description: {
            Text("Docker Hub is throttling requests. Try again shortly.", bundle: .module)
        }
    }

    private func unavailableState(
        _ detail: ErrorDetail, retry: @escaping () -> Void
    ) -> some View {
        ContentUnavailableView {
            Label(detail.title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(detail.explanation)
        } actions: {
            Button {
                retry()
            } label: {
                Text("Try Again", bundle: .module)
            }
        }
    }

    /// The trailing "Load More" row shared by both lists; a small spinner replaces the
    /// label while the next page is in flight.
    private func loadMoreRow(isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Load More", bundle: .module)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

/// One repository result: name (with the official-image badge), description, and compact
/// star/pull counts.
private struct RegistryRepositoryRow: View {
    let repository: RegistryRepository

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: repository.name)
                    if repository.isOfficial {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                            .help(Text("Official image", bundle: .module))
                            .accessibilityLabel(Text("Official image", bundle: .module))
                    }
                }
                if let description = repository.shortDescription {
                    Text(verbatim: description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                    compactCount(repository.starCount)
                }
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.circle")
                    compactCount(repository.pullCount.map(Int.init))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func compactCount(_ count: Int?) -> some View {
        if let count {
            Text(count, format: .number.notation(.compactName))
        } else {
            Text(verbatim: "—")
        }
    }
}

/// One tag row: the monospaced tag name with its last update and compressed size.
private struct RegistryTagRow: View {
    let tag: RegistryTag

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: tag.name)
                .font(.system(.body, design: .monospaced))
            Spacer()
            HStack(spacing: 8) {
                if let updated = tag.lastUpdated {
                    Text(updated, format: .relative(presentation: .named))
                } else {
                    Text(verbatim: "—")
                }
                if let size = tag.sizeBytes {
                    Text(size, format: .byteCount(style: .file))
                } else {
                    Text(verbatim: "—")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
