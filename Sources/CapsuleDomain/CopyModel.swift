//
//  CopyModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Backs the copy sheet:
//  a host endpoint (a local URL) and a container endpoint (`id:/abs/path`), validated BEFORE
//  spawning so the `container:path` semantics are caught early with an example. The copy runs
//  as a `.copy` Activity task; the container side can be browsed via a best-effort `ls`.

import CapsuleBackend
import Foundation
import Observation

/// A UI-facing directory entry — the domain's own shape so the UI never names a backend
/// type (mirrors how `LogLine` wraps `OutputLine`).
public struct ContainerFileItem: Sendable, Equatable, Identifiable {
    public let name: String
    public let isDirectory: Bool

    public var id: String { name }

    public init(name: String, isDirectory: Bool) {
        self.name = name
        self.isDirectory = isDirectory
    }
}

public enum CopyDirection: String, Sendable, CaseIterable, Identifiable {
    case toContainer
    case fromContainer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .toContainer: return "Host → Container"
        case .fromContainer: return "Container → Host"
        }
    }
}

@MainActor
@Observable
public final class CopyModel {
    public var direction: CopyDirection = .toContainer
    public var hostURL: URL?
    public var containerID: String = ""
    public var containerPath: String = ""

    private let backend: any ContainerBackend
    private let taskCenter: TaskCenter
    private let onActivity: @MainActor (String) -> Void

    public init(
        backend: any ContainerBackend,
        taskCenter: TaskCenter,
        onActivity: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.backend = backend
        self.taskCenter = taskCenter
        self.onActivity = onActivity
    }

    public func reset(containerID: String = "") {
        direction = .toContainer
        hostURL = nil
        self.containerID = containerID
        containerPath = ""
    }

    /// Why the copy can't run yet (host endpoint, container id, and an ABSOLUTE container
    /// path are all required), or nil when it's ready. The message carries an example so the
    /// `container:path` semantics are obvious before spawning.
    public var validationMessage: String? {
        if hostURL == nil { return "Choose a host file or folder." }
        if containerID.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Enter the container id."
        }
        let path = containerPath.trimmingCharacters(in: .whitespaces)
        if path.isEmpty || !path.hasPrefix("/") {
            return "Container path must be absolute, e.g. \(exampleID):/app/file"
        }
        return nil
    }

    public var canCopy: Bool { validationMessage == nil }

    /// A sample `id:/path` for the UI's example/help text.
    public var exampleID: String {
        let trimmed = containerID.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "container" : trimmed
    }

    /// The faithful `container copy …` invocation, composing the `id:path` endpoint exactly
    /// as `CLIContainerBackend.copyTo/FromContainer` does, so the preview matches what runs.
    public var commandInvocation: CommandInvocation {
        let id = containerID.trimmingCharacters(in: .whitespaces)
        let path = containerPath.trimmingCharacters(in: .whitespaces)
        let containerEndpoint = "\(id):\(path)"
        let host = hostURL?.path ?? ""
        switch direction {
        case .toContainer:
            return CommandInvocation(CLICommand.copy(source: host, destination: containerEndpoint))
        case .fromContainer:
            return CommandInvocation(CLICommand.copy(source: containerEndpoint, destination: host))
        }
    }

    /// Runs the copy as a `.copy` Activity task in the validated direction.
    @discardableResult
    public func copy() -> OperationTask? {
        guard canCopy, let hostURL else { return nil }
        let id = containerID.trimmingCharacters(in: .whitespaces)
        let path = containerPath.trimmingCharacters(in: .whitespaces)
        let direction = direction
        let title =
            direction == .toContainer
            ? "Copy \(hostURL.lastPathComponent) → \(id):\(path)"
            : "Copy \(id):\(path) → \(hostURL.lastPathComponent)"
        onActivity(title)
        return taskCenter.runAsync(kind: .copy, title: title) { [backend] in
            switch direction {
            case .toContainer:
                try await backend.copyToContainer(
                    source: hostURL, containerID: id, containerPath: path)
            case .fromContainer:
                try await backend.copyFromContainer(
                    containerID: id, containerPath: path, destination: hostURL)
            }
        }
    }

    /// Best-effort one-level listing of a container directory (requires a running container
    /// with `ls`); degrades to an empty list rather than throwing into the UI.
    public func browse(path: String) async -> [ContainerFileItem] {
        let id = containerID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return [] }
        let entries = (try? await backend.listContainerDirectory(id: id, path: path)) ?? []
        return entries.map { ContainerFileItem(name: $0.name, isDirectory: $0.isDirectory) }
    }
}
