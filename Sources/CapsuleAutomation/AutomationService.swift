//
//  AutomationService.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The single Sendable facade that every automation surface — App Intents and AppleScript —
//  invokes. It wraps the `ContainerBackend` port so automation runs headlessly (off the main
//  actor, with no UI models) and stays trivially testable: inject a fake backend.
//

import CapsuleBackend
import Foundation

/// A backend-agnostic description of Capsule's automatable operations.
///
/// Kept deliberately small and value-typed so both App Intents (`@Dependency`) and the
/// AppleScript command bridge resolve one shared implementation. The concrete
/// ``LiveAutomationService`` drives the `container` CLI via the backend port; tests supply
/// a fake `ContainerBackend`.
public protocol AutomationService: Sendable {
    /// Starts the container system service.
    func startServices() async throws

    /// Stops the container system service.
    func stopServices() async throws

    /// Runs a detached container from `image`, returning the new container id.
    @discardableResult
    func runContainer(image: String, name: String?) async throws -> String

    /// Pulls an image, returning the accumulated progress transcript.
    @discardableResult
    func pullImage(reference: String, platform: String?) async throws -> String

    /// Builds an image from a context directory + tag, returning the build transcript.
    @discardableResult
    func buildImage(contextDirectory: URL, tag: String) async throws -> String

    /// Follows (snapshots) a container's logs, returning up to `tail` recent lines joined.
    func containerLogs(id: String, tail: Int?) async throws -> String

    /// Copies a host file into a running container.
    func copyToContainer(source: URL, containerID: String, containerPath: String) async throws

    /// Exports a container's filesystem to a tar archive on disk.
    func exportContainer(id: String, to url: URL) async throws

    /// Reclaims space across containers, images, and volumes; returns a human summary.
    @discardableResult
    func reclaimSpace() async throws -> String

    /// Lists container ids (names when present), one per line.
    func listContainers(all: Bool) async throws -> [String]

    /// Lists image references, one per line.
    func listImages() async throws -> [String]
}

/// The production ``AutomationService`` — every call maps to one `ContainerBackend` port method.
public struct LiveAutomationService: AutomationService {
    private let backend: any ContainerBackend

    public init(backend: any ContainerBackend) {
        self.backend = backend
    }

    public func startServices() async throws {
        try await backend.startSystem()
    }

    public func stopServices() async throws {
        try await backend.stopSystem()
    }

    @discardableResult
    public func runContainer(image: String, name: String?) async throws -> String {
        let config = RunConfiguration(image: image, name: name, detach: true)
        return try await backend.runContainer(config)
    }

    @discardableResult
    public func pullImage(reference: String, platform: String?) async throws -> String {
        try await collect(backend.pullImage(reference: reference, platform: platform))
    }

    @discardableResult
    public func buildImage(contextDirectory: URL, tag: String) async throws -> String {
        let config = BuildConfiguration(contextDirectory: contextDirectory, tag: tag)
        return try await collect(backend.buildImage(config))
    }

    public func containerLogs(id: String, tail: Int?) async throws -> String {
        let lines = try await backend.fetchLogs(container: id, tail: tail, boot: false)
        return lines.map(\.text).joined(separator: "\n")
    }

    public func copyToContainer(
        source: URL, containerID: String, containerPath: String
    ) async throws {
        try await backend.copyToContainer(
            source: source, containerID: containerID, containerPath: containerPath)
    }

    public func exportContainer(id: String, to url: URL) async throws {
        try await backend.exportContainer(id: id, to: url)
    }

    @discardableResult
    public func reclaimSpace() async throws -> String {
        let containers = try await backend.pruneContainers()
        let images = try await backend.pruneImages(all: true)
        let volumes = try await backend.pruneVolumes()
        return [
            "Containers: \(containers.reclaimedDescription ?? "reclaimed")",
            "Images: \(images.reclaimedDescription ?? "reclaimed")",
            "Volumes: \(volumes.reclaimedDescription ?? "reclaimed")",
        ].joined(separator: "\n")
    }

    public func listContainers(all: Bool) async throws -> [String] {
        try await backend.listContainers(all: all).map { $0.name.isEmpty ? $0.id : $0.name }
    }

    public func listImages() async throws -> [String] {
        try await backend.listImages().map(\.reference)
    }

    /// Drains a progress stream into a single transcript string (automation callers want a
    /// value, not a live feed).
    private func collect(_ stream: AsyncThrowingStream<OutputLine, Error>) async throws -> String {
        var lines: [String] = []
        for try await line in stream {
            lines.append(line.text)
        }
        return lines.joined(separator: "\n")
    }
}
