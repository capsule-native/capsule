//
//  ContainerBackend.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// The port that every container backend must satisfy.
///
/// Concrete adapters (the `container` CLI today; potentially a daemon socket or an
/// in-memory mock tomorrow) conform to this protocol. The domain talks to this
/// abstraction and never to a concrete backend, which keeps the runtime swappable and
/// the higher layers testable.
///
/// The protocol spans the command families Capsule drives — system, containers, images,
/// volumes, networks, registries, machines, and the builder — plus a low-level
/// ``runRaw(_:)`` / ``streamRaw(_:)`` escape hatch for anything not yet modelled. Adding
/// a new command is intentionally cheap: declare it here, implement it in each adapter,
/// and surface it from the domain. No UI changes are required.
public protocol ContainerBackend: Sendable {
    // MARK: System & capabilities

    /// Returns version information for the backend client (and server, if running).
    func version() async throws -> BackendVersion

    /// Probes which command families this build/state actually supports.
    func capabilities() async throws -> BackendCapabilities

    /// Reports whether the container system service is currently running.
    ///
    /// Throws (rather than returning ``SystemRunState/stopped``) when the service cannot
    /// be reached at all — a missing executable, an XPC/connection failure, a daemon that
    /// never came up — so callers can distinguish "cleanly stopped" from "unreachable".
    func systemStatus() async throws -> SystemRunState

    /// Starts the container system service (`container system start`).
    func startSystem() async throws

    /// Stops the container system service (`container system stop`).
    func stopSystem() async throws

    // MARK: Containers

    /// Lists containers; when `all` is false only running containers are returned.
    func listContainers(all: Bool) async throws -> [ContainerSummary]

    /// Inspects a single container, retaining the raw payload alongside the decoded row.
    func inspectContainer(id: String) async throws -> Parsed<ContainerSummary>

    func startContainer(id: String) async throws
    func stopContainer(id: String, options: StopOptions) async throws
    func removeContainer(id: String, force: Bool) async throws

    /// Sends a signal (default KILL when `signal` is nil) to a running container.
    func killContainer(id: String, signal: String?) async throws

    /// Removes all stopped containers; returns the CLI's best-effort reclaimed summary.
    func pruneContainers() async throws -> PruneResult

    /// Exports a container's filesystem as a tar archive to `url`.
    func exportContainer(id: String, to url: URL) async throws

    /// One-shot resource statistics for the given containers.
    func containerStats(ids: [String]) async throws -> [ContainerStatsSample]

    /// Streams resource statistics, polling `interval` between one-shot reads. The stream
    /// finishes cleanly when cancelled (consumer breaks out / task cancelled).
    func streamContainerStats(
        ids: [String], interval: Duration
    )
        -> AsyncThrowingStream<[ContainerStatsSample], Error>

    /// Streams a container's logs line-by-line, following until cancelled.
    func followLogs(container id: String) -> AsyncThrowingStream<OutputLine, Error>

    // MARK: Images

    func listImages() async throws -> [ImageSummary]
    func inspectImage(reference: String) async throws -> Parsed<ImageSummary>
    func removeImage(reference: String) async throws

    /// Pulls an image, streaming progress line-by-line.
    func pullImage(reference: String) -> AsyncThrowingStream<OutputLine, Error>

    // MARK: Volumes / networks / registries / machines / builder

    func listVolumes() async throws -> [VolumeSummary]
    func listNetworks() async throws -> [NetworkSummary]
    func listRegistries() async throws -> [RegistrySummary]
    func listMachines() async throws -> [MachineSummary]
    func builderStatus() async throws -> BuilderStatus

    // MARK: Escape hatches

    /// Runs an arbitrary argument vector and returns its raw result (never throwing on a
    /// non-zero exit — the caller inspects ``RawCommandOutput/exitCode``).
    func runRaw(_ arguments: [String]) async throws -> RawCommandOutput

    /// Streams an arbitrary argument vector line-by-line (build, push, follow, …).
    func streamRaw(_ arguments: [String]) -> AsyncThrowingStream<OutputLine, Error>
}

extension ContainerBackend {
    /// Convenience: lists only running containers.
    public func listContainers() async throws -> [ContainerSummary] {
        try await listContainers(all: false)
    }

    /// Convenience: stop with default options (CLI default signal + timeout).
    public func stopContainer(id: String) async throws {
        try await stopContainer(id: id, options: .default)
    }
}
