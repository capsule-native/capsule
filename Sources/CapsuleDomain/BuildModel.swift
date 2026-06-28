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
public enum BuildPreset: String, Sendable, CaseIterable, Identifiable {
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

@MainActor
@Observable
public final class BuildModel {
    public var draft = BuildDraft()

    private let backend: any ContainerBackend
    private let taskCenter: TaskCenter
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void
    private let reloadList: @MainActor () async -> Void

    public init(
        backend: any ContainerBackend,
        taskCenter: TaskCenter,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in },
        reloadList: @escaping @MainActor () async -> Void = {}
    ) {
        self.backend = backend
        self.taskCenter = taskCenter
        self.normalize = normalize
        self.onActivity = onActivity
        self.reloadList = reloadList
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

    private func start(_ config: BuildConfiguration) -> OperationTask {
        onActivity("Building \(config.tag)…")
        return taskCenter.runStreaming(
            kind: .build, title: "Build \(config.tag)",
            onSuccess: { [reloadList] in await reloadList() }
        ) { [backend] in
            backend.buildImage(config)
        }
    }
}
