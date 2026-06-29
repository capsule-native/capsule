//
//  VolumeBrowserModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The volumes read
//  surface, mirroring `ImageBrowserModel`: a loaded list with a live query (search + sort),
//  a multi-selection, and raw-retaining inspect. On refresh it also reads the container list
//  to build an AttachmentIndex and stamps each volume's `attachedContainers`. Volume actions
//  (create/delete/prune) live in `VolumeActionsModel`.

import CapsuleBackend
import Foundation
import Observation

/// The load state of the volume list, kept separate from `rows` so the UI can distinguish
/// "service unreachable" from "no volumes" from "no matches".
public enum VolumeLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case unavailable(ErrorDetail)
}

/// A volume inspection: the decoded domain value (nil if the payload drifted) paired with
/// the exact raw JSON, so the inspector can always show *something*.
public struct VolumeInspection: Sendable, Equatable {
    public var value: Volume?
    public var rawJSON: String

    public init(value: Volume?, rawJSON: String) {
        self.value = value
        self.rawJSON = rawJSON
    }
}

@MainActor
@Observable
public final class VolumeBrowserModel {
    public private(set) var allVolumes: [Volume] = []
    public private(set) var loadState: VolumeLoadState = .idle

    public var searchText: String = ""
    public var selection: Set<Volume.ID> = []

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.backend = backend
        self.normalize = normalize
        self.onActivity = onActivity
    }

    // MARK: Derived views

    /// Volumes passing the search term, ordered by name.
    public var rows: [Volume] {
        allVolumes
            .filter { matchesSearch($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public var selectedVolumes: [Volume] {
        allVolumes.filter { selection.contains($0.id) }
    }

    /// The service is up but there are genuinely no volumes.
    public var isEmptyButHealthy: Bool {
        loadState == .loaded && allVolumes.isEmpty
    }

    /// There are volumes, but the search matched none.
    public var noMatches: Bool {
        loadState == .loaded && !allVolumes.isEmpty && rows.isEmpty
    }

    private func matchesSearch(_ volume: Volume) -> Bool {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        return volume.name.localizedCaseInsensitiveContains(term)
            || (volume.source?.localizedCaseInsensitiveContains(term) ?? false)
    }

    // MARK: Loading

    public func refresh() async {
        loadState = .loading
        do {
            let summaries = try await backend.listVolumes()
            let index = await attachmentIndex()
            allVolumes = summaries.map { summary in
                Volume(
                    summary: summary,
                    attachedContainers: index.containers(forVolume: summary.name))
            }
            selection = selection.intersection(Set(allVolumes.map(\.id)))
            loadState = .loaded
            onActivity("Loaded \(allVolumes.count) volume(s).")
        } catch {
            allVolumes = []
            let detail = normalize(error).detail
            onActivity("Failed to load volumes: \(detail.title)")
            loadState = .unavailable(detail)
        }
    }

    /// Inspects one volume, mapping the backend's raw-retaining `Parsed` into the domain
    /// `VolumeInspection`. Never throws: a failure yields an empty raw payload.
    public func inspect(name: String) async -> VolumeInspection {
        do {
            let parsed = try await backend.inspectVolume(names: [name])
            return VolumeInspection(
                value: parsed.value?.first.map { Volume(summary: $0) },
                rawJSON: parsed.raw)
        } catch {
            return VolumeInspection(value: nil, rawJSON: "")
        }
    }

    /// Builds the best-effort attachment cross-reference from the current container list.
    /// A container-list failure degrades gracefully to an empty index — volumes still load.
    private func attachmentIndex() async -> AttachmentIndex {
        let containers = (try? await backend.listContainers(all: true)) ?? []
        return AttachmentIndex.build(
            from: containers.map(Container.init(summary:)).map(
                ContainerAttachmentInfo.init(container:)))
    }
}
