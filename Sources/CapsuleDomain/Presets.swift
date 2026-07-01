//
//  Presets.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Concrete
//  persistence (UserDefaults) lives in the composition root so the domain owns no
//  storage-key knowledge; this file defines the saved-preset value types, the seam, and
//  an in-memory double — mirroring the `ScopeStore` triad.

import Foundation

/// A named, saved Quick Run configuration, re-invokable from the palette or menu.
public struct SavedRunPreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var draft: RunDraft

    public init(id: UUID = UUID(), name: String, draft: RunDraft) {
        self.id = id
        self.name = name
        self.draft = draft
    }
}

/// A named, saved Build configuration, re-invokable from the palette or menu.
public struct SavedBuildPreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var draft: BuildDraft

    public init(id: UUID = UUID(), name: String, draft: BuildDraft) {
        self.id = id
        self.name = name
        self.draft = draft
    }
}

/// Persists the user's saved Run/Build presets. Injected into ``RunModel``/``BuildModel`` so
/// the domain stays free of any concrete persistence and remains unit-testable.
public protocol PresetStore: Sendable {
    func loadRunPresets() -> [SavedRunPreset]
    func saveRunPresets(_ presets: [SavedRunPreset])
    func loadBuildPresets() -> [SavedBuildPreset]
    func saveBuildPresets(_ presets: [SavedBuildPreset])
}

/// A thread-safe, in-memory ``PresetStore`` — the models' default (ephemeral) and the
/// test double.
public final class InMemoryPresetStore: PresetStore, @unchecked Sendable {
    private let lock = NSLock()
    private var runPresets: [SavedRunPreset]
    private var buildPresets: [SavedBuildPreset]

    public init(
        runPresets: [SavedRunPreset] = [],
        buildPresets: [SavedBuildPreset] = []
    ) {
        self.runPresets = runPresets
        self.buildPresets = buildPresets
    }

    public func loadRunPresets() -> [SavedRunPreset] {
        lock.lock()
        defer { lock.unlock() }
        return runPresets
    }

    public func saveRunPresets(_ presets: [SavedRunPreset]) {
        lock.lock()
        defer { lock.unlock() }
        runPresets = presets
    }

    public func loadBuildPresets() -> [SavedBuildPreset] {
        lock.lock()
        defer { lock.unlock() }
        return buildPresets
    }

    public func saveBuildPresets(_ presets: [SavedBuildPreset]) {
        lock.lock()
        defer { lock.unlock() }
        buildPresets = presets
    }
}
