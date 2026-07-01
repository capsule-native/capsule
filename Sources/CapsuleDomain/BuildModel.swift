//
//  BuildModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Owns the Build flow:
//  a UI-friendly draft + presets, validation into a `BuildConfiguration`, a streaming build
//  task (raw transcript never hidden), and a "plain progress" retry that re-runs the build
//  with `--progress plain` for diagnosable, uncollapsed output.

import CapsuleBackend
import Foundation
import Observation

/// A one-tap build preset that seeds the cache/progress flags.
public enum BuildPreset: String, Sendable, Codable, CaseIterable, Identifiable {
    case standard
    case noCache
    case plainProgress

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "Standard"
        case .noCache: return "No cache"
        case .plainProgress: return "Plain progress"
        }
    }
}

/// A UI-friendly draft of a build.
public struct BuildDraft: Sendable, Equatable {
    public var contextDirectory: URL?
    public var tag: String = ""
    public var dockerfile: String = ""
    /// `KEY=value` rows; blank rows are ignored.
    public var buildArgRows: [String] = []
    public var noCache: Bool = false
    public var preset: BuildPreset = .standard

    public init() {}
}

extension BuildDraft: Codable {
    private enum CodingKeys: String, CodingKey {
        case contextDirectory, tag, dockerfile, buildArgRows, noCache, preset
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        // The app is unsandboxed, so the context folder persists as a plain path
        // (no security-scoped bookmark) rather than the synthesized URL container.
        if let path = try container.decodeIfPresent(String.self, forKey: .contextDirectory) {
            self.contextDirectory = URL(fileURLWithPath: path)
        }
        self.tag = try container.decode(String.self, forKey: .tag)
        self.dockerfile = try container.decode(String.self, forKey: .dockerfile)
        self.buildArgRows = try container.decode([String].self, forKey: .buildArgRows)
        self.noCache = try container.decode(Bool.self, forKey: .noCache)
        self.preset = try container.decode(BuildPreset.self, forKey: .preset)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(contextDirectory?.path, forKey: .contextDirectory)
        try container.encode(tag, forKey: .tag)
        try container.encode(dockerfile, forKey: .dockerfile)
        try container.encode(buildArgRows, forKey: .buildArgRows)
        try container.encode(noCache, forKey: .noCache)
        try container.encode(preset, forKey: .preset)
    }
}

@MainActor
@Observable
public final class BuildModel {
    public var draft = BuildDraft()
    /// The user's saved build presets, loaded from the injected ``PresetStore``.
    public private(set) var buildPresets: [SavedBuildPreset] = []

    private let backend: any ContainerBackend
    private let taskCenter: TaskCenter
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void
    private let reloadList: @MainActor () async -> Void
    private let presetStore: any PresetStore

    public init(
        backend: any ContainerBackend,
        taskCenter: TaskCenter,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in },
        reloadList: @escaping @MainActor () async -> Void = {},
        presetStore: any PresetStore = InMemoryPresetStore()
    ) {
        self.backend = backend
        self.taskCenter = taskCenter
        self.normalize = normalize
        self.onActivity = onActivity
        self.reloadList = reloadList
        self.presetStore = presetStore
    }

    public func reset() {
        draft = BuildDraft()
    }

    /// Validates the draft into a `BuildConfiguration`, applying the preset's cache/progress
    /// flags (a preset OR's with the explicit no-cache toggle), or returns the first error.
    public func validatedConfiguration() -> Result<BuildConfiguration, CapsuleError> {
        guard let context = draft.contextDirectory else {
            return .failure(
                .invalidInput(field: "context", message: "Choose a build context folder."))
        }
        let tag = draft.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else {
            return .failure(.invalidInput(field: "tag", message: "Enter a tag for the image."))
        }
        let dockerfile = draft.dockerfile.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = BuildConfiguration(
            contextDirectory: context,
            tag: tag,
            dockerfile: dockerfile.isEmpty ? nil : dockerfile,
            buildArgs: draft.buildArgRows
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            noCache: draft.noCache || draft.preset == .noCache,
            plainProgress: draft.preset == .plainProgress)
        return .success(config)
    }

    /// The faithful `container build …` invocation for the live preview; falls back to
    /// `container build` while the draft is incomplete so the field never shows a stub.
    public var commandInvocation: CommandInvocation {
        switch validatedConfiguration() {
        case let .success(config):
            return CommandInvocation(config.arguments)
        case .failure:
            return CommandInvocation(["build"])
        }
    }

    /// Starts the build as a streaming Activity task; reloads the image list on success.
    @discardableResult
    public func build() -> OperationTask? {
        guard case let .success(config) = validatedConfiguration() else { return nil }
        return start(config)
    }

    /// Re-runs the build with `--progress plain` (the diagnosable, uncollapsed retry).
    @discardableResult
    public func retryPlain() -> OperationTask? {
        guard case var .success(config) = validatedConfiguration() else { return nil }
        config.plainProgress = true
        return start(config)
    }

    // MARK: Saved presets

    /// Loads saved build presets from the store into ``buildPresets``.
    public func loadPresets() {
        buildPresets = presetStore.loadBuildPresets()
    }

    /// Saves the current draft as a new named preset and persists the list.
    public func savePreset(name: String) {
        let preset = SavedBuildPreset(name: name, draft: draft)
        buildPresets.append(preset)
        presetStore.saveBuildPresets(buildPresets)
        onActivity("Saved build preset “\(name)”.")
    }

    /// Removes a preset and persists the updated list.
    public func deletePreset(_ preset: SavedBuildPreset) {
        buildPresets.removeAll { $0.id == preset.id }
        presetStore.saveBuildPresets(buildPresets)
    }

    /// Loads a preset's draft into the sheet, ready to build.
    public func apply(_ preset: SavedBuildPreset) {
        draft = preset.draft
    }

    private func start(_ config: BuildConfiguration) -> OperationTask {
        onActivity("Building \(config.tag)…")
        return taskCenter.runStreaming(
            kind: .build, title: "Build \(config.tag)",
            invocation: CommandInvocation(config.arguments),
            onSuccess: { [reloadList] in await reloadList() }
        ) { [backend] in
            backend.buildImage(config)
        }
    }
}
