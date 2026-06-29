//
//  MachineBrowserModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import Foundation
import Observation

/// The load state of the machine list, kept separate from `rows` so the UI can distinguish
/// "service unreachable" from "no machines" from "no matches".
public enum MachineLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case unavailable(ErrorDetail)
}

/// A machine inspection: the decoded domain value (nil if the payload drifted) paired with
/// the exact raw JSON, so the inspector can always show *something*.
public struct MachineInspection: Sendable, Equatable {
    public var value: Machine?
    public var rawJSON: String

    public init(value: Machine?, rawJSON: String) {
        self.value = value
        self.rawJSON = rawJSON
    }
}

@MainActor
@Observable
public final class MachineBrowserModel {
    public private(set) var allMachines: [Machine] = []
    public private(set) var loadState: MachineLoadState = .idle

    public var searchText: String = ""
    public var selection: Set<Machine.ID> = []

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

    /// Machines passing the search term, ordered by name.
    public var rows: [Machine] {
        allMachines
            .filter { matchesSearch($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public var selectedMachines: [Machine] {
        allMachines.filter { selection.contains($0.id) }
    }

    /// The default machine, if any.
    public var defaultMachine: Machine? {
        allMachines.first { $0.isDefault }
    }

    /// The service is up but there are genuinely no machines (distinct from a down service
    /// and from a search that matched nothing).
    public var isEmptyButHealthy: Bool {
        loadState == .loaded && allMachines.isEmpty
    }

    /// There are machines, but the active search matched none.
    public var noMatches: Bool {
        loadState == .loaded && !allMachines.isEmpty && rows.isEmpty
    }

    private func matchesSearch(_ machine: Machine) -> Bool {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        return machine.name.localizedCaseInsensitiveContains(term)
            || machine.state.label.localizedCaseInsensitiveContains(term)
    }

    // MARK: Loading

    public func refresh() async {
        loadState = .loading
        do {
            let summaries = try await backend.listMachines()
            allMachines = summaries.map { Machine(summary: $0) }
            selection = selection.intersection(Set(allMachines.map(\.id)))
            loadState = .loaded
            onActivity("Loaded \(allMachines.count) machine(s).")
        } catch {
            allMachines = []
            let detail = normalize(error).detail
            onActivity("Failed to load machines: \(detail.title)")
            loadState = .unavailable(detail)
        }
    }

    /// Inspects one machine, mapping the backend's raw-retaining `Parsed` into the domain
    /// `MachineInspection`. Never throws: a failure yields an empty raw payload.
    public func inspect(id: String) async -> MachineInspection {
        do {
            let parsed = try await backend.inspectMachine(id: id)
            return MachineInspection(
                value: parsed.value.map { Machine(summary: $0) },
                rawJSON: parsed.raw)
        } catch {
            return MachineInspection(value: nil, rawJSON: "")
        }
    }
}
