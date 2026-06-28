//
//  ContainerBrowserModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The model is
//  `@Observable` (from `Observation`, not SwiftUI) so the UI can bind to it while the
//  domain stays UI-free. It maps the backend's raw `Parsed<ContainerSummary>` into the
//  domain `ContainerInspection` so no backend wire type reaches the UI.

import CapsuleBackend
import Foundation
import Observation

/// The load state of the container list, kept separate from the filtered `rows` so the UI
/// can distinguish "service unreachable" from "no containers" from "no matches".
public enum ContainerLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case unavailable(ErrorDetail)
}

/// A container inspection: the decoded domain value (nil if the payload drifted) paired
/// with the exact raw JSON, so the inspector can always show *something*.
public struct ContainerInspection: Sendable, Equatable {
    public var value: Container?
    public var rawJSON: String

    public init(value: Container?, rawJSON: String) {
        self.value = value
        self.rawJSON = rawJSON
    }
}

/// Owns the containers browser surface: the loaded list, the live query (search + state
/// filter), the multi-selection, and the user's saved scopes. Lifecycle actions are
/// Milestone 5B and deliberately absent here.
@MainActor
@Observable
public final class ContainerBrowserModel {
    public private(set) var allContainers: [Container] = []
    public private(set) var loadState: ContainerLoadState = .idle
    public private(set) var savedScopes: [ContainerScope] = []

    public var searchText: String = ""
    public var stateFilter: ContainerStateFilter = .all
    public var selection: Set<Container.ID> = []

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let scopeStore: any ScopeStore
    private let onActivity: @MainActor (String) -> Void

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        scopeStore: any ScopeStore = InMemoryScopeStore(),
        onActivity: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.backend = backend
        self.normalize = normalize
        self.scopeStore = scopeStore
        self.onActivity = onActivity
    }

    // MARK: Derived views

    /// Containers passing the active state filter and search term, sorted by name.
    public var rows: [Container] {
        allContainers
            .filter { stateFilter.matches($0.state) }
            .filter { matchesSearch($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public var selectedContainers: [Container] {
        allContainers.filter { selection.contains($0.id) }
    }

    /// The service is up but there are genuinely no containers (distinct from a down
    /// service and from a filter that matched nothing).
    public var isEmptyButHealthy: Bool {
        loadState == .loaded && allContainers.isEmpty
    }

    /// There are containers, but the active filter/search matched none.
    public var noMatches: Bool {
        loadState == .loaded && !allContainers.isEmpty && rows.isEmpty
    }

    private func matchesSearch(_ container: Container) -> Bool {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        return container.name.localizedCaseInsensitiveContains(term)
            || container.image.localizedCaseInsensitiveContains(term)
            || container.id.localizedCaseInsensitiveContains(term)
    }

    // MARK: Loading

    public func refresh() async {
        loadState = .loading
        do {
            let summaries = try await backend.listContainers(all: true)
            allContainers = summaries.map(Container.init(summary:))
            selection = selection.intersection(Set(allContainers.map(\.id)))
            loadState = .loaded
            onActivity("Loaded \(allContainers.count) container(s).")
        } catch {
            allContainers = []
            let detail = normalize(error).detail
            onActivity("Failed to load containers: \(detail.title)")
            loadState = .unavailable(detail)
        }
    }

    /// Inspects one container, mapping the backend's raw-retaining `Parsed` into the
    /// domain `ContainerInspection`. Never throws: a failure yields an empty raw payload.
    public func inspect(id: String) async -> ContainerInspection {
        do {
            let parsed = try await backend.inspectContainer(id: id)
            return ContainerInspection(
                value: parsed.value.map(Container.init(summary:)),
                rawJSON: parsed.raw
            )
        } catch {
            return ContainerInspection(value: nil, rawJSON: "")
        }
    }

    // MARK: Saved scopes

    public func loadScopes() {
        savedScopes = scopeStore.load()
    }

    public func saveCurrentScope(name: String) {
        let scope = ContainerScope(
            id: UUID().uuidString,
            name: name,
            stateFilter: stateFilter,
            searchTerm: searchText
        )
        savedScopes.append(scope)
        scopeStore.save(savedScopes)
        onActivity("Saved scope “\(name)”.")
    }

    public func removeScope(_ scope: ContainerScope) {
        savedScopes.removeAll { $0.id == scope.id }
        scopeStore.save(savedScopes)
    }

    /// Applies a scope's filter + search term to the live query.
    public func activate(_ scope: ContainerScope) {
        stateFilter = scope.stateFilter
        searchText = scope.searchTerm
    }
}
