//
//  NetworkBrowserModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The networks read
//  surface, mirroring `ImageBrowserModel`: a loaded list with a live query, a multi-
//  selection, and raw-retaining inspect. On refresh it also reads `container list -a`,
//  builds an `AttachmentIndex`, and stamps each network's `connectedContainers`. Network
//  mutations (create/delete/prune) live in `NetworkActionsModel`.

import CapsuleBackend
import Foundation
import Observation

/// The load state of the network list, kept separate from `rows` so the UI can distinguish
/// "service unreachable" from "no networks" from "no matches".
public enum NetworkLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case unavailable(ErrorDetail)
}

/// A network inspection: the decoded domain value (nil if the payload drifted) paired with
/// the exact raw JSON, so the inspector can always show *something*.
public struct NetworkInspection: Sendable, Equatable {
    public var value: Network?
    public var rawJSON: String

    public init(value: Network?, rawJSON: String) {
        self.value = value
        self.rawJSON = rawJSON
    }
}

@MainActor
@Observable
public final class NetworkBrowserModel {
    public private(set) var allNetworks: [Network] = []
    public private(set) var loadState: NetworkLoadState = .idle

    public var searchText: String = ""
    public var selection: Set<Network.ID> = []

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

    /// Networks passing the search term, ordered by name.
    public var rows: [Network] {
        allNetworks
            .filter { matchesSearch($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public var selectedNetworks: [Network] {
        allNetworks.filter { selection.contains($0.id) }
    }

    /// The service is up but there are genuinely no networks (distinct from a down service
    /// and from a search that matched nothing).
    public var isEmptyButHealthy: Bool {
        loadState == .loaded && allNetworks.isEmpty
    }

    /// There are networks, but the active search matched none.
    public var noMatches: Bool {
        loadState == .loaded && !allNetworks.isEmpty && rows.isEmpty
    }

    private func matchesSearch(_ network: Network) -> Bool {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        return network.name.localizedCaseInsensitiveContains(term)
            || (network.ipv4Subnet?.localizedCaseInsensitiveContains(term) ?? false)
            || (network.ipv6Subnet?.localizedCaseInsensitiveContains(term) ?? false)
            || (network.mode?.localizedCaseInsensitiveContains(term) ?? false)
    }

    // MARK: Loading

    public func refresh() async {
        loadState = .loading
        do {
            let summaries = try await backend.listNetworks()
            let attachments = await loadAttachmentIndex()
            allNetworks = summaries.map { summary in
                Network(
                    summary: summary,
                    connectedContainers: attachments.containers(forNetwork: summary.name))
            }
            selection = selection.intersection(Set(allNetworks.map(\.id)))
            loadState = .loaded
            onActivity("Loaded \(allNetworks.count) network(s).")
        } catch {
            allNetworks = []
            let detail = normalize(error).detail
            onActivity("Failed to load networks: \(detail.title)")
            loadState = .unavailable(detail)
        }
    }

    /// Inspects one network, mapping the backend's raw-retaining `Parsed` into the domain
    /// `NetworkInspection`. Never throws: a failure yields an empty raw payload.
    public func inspect(name: String) async -> NetworkInspection {
        do {
            let parsed = try await backend.inspectNetwork(names: [name])
            let summary = parsed.value?.first
            return NetworkInspection(
                value: summary.map { Network(summary: $0) },
                rawJSON: parsed.raw)
        } catch {
            return NetworkInspection(value: nil, rawJSON: "")
        }
    }

    // MARK: Attachment cross-reference

    /// Best-effort read of `container list -a` → an attachment index. A failure (e.g. the
    /// service is mid-recovery) degrades to an empty index rather than failing the list.
    private func loadAttachmentIndex() async -> AttachmentIndex {
        let containers = ((try? await backend.listContainers(all: true)) ?? [])
            .map(Container.init(summary:))
        return AttachmentIndex.build(from: containers.map(ContainerAttachmentInfo.init(container:)))
    }
}
