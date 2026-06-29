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

    /// Disk usage for images, containers, and volumes (`system df`).
    func systemDiskUsage() async throws -> StorageUsage

    /// Full component list from `container system version` (client, apiserver, …).
    func systemComponentVersions() async throws -> [ComponentVersion]

    /// Merged system properties as structured sections (`container system property list --format json`).
    func systemProperties() async throws -> SystemProperties

    /// Raw TOML text from `container system property list` (verbatim stdout, for editor/export).
    func systemPropertiesTOML() async throws -> String

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

    /// Fetches a snapshot of a container's logs (no follow). `tail` limits to the last N
    /// lines; `boot` requests the boot log instead of stdio.
    func fetchLogs(container id: String, tail: Int?, boot: Bool) async throws -> [OutputLine]

    /// Runs a container. Only the **detached** path goes through the port (interactive
    /// `run -it` is a terminal session); returns the new container id (parsed from stdout).
    func runContainer(_ config: RunConfiguration) async throws -> String

    /// Copies a host file/folder into a running container (`copy <src> <id>:<path>`).
    func copyToContainer(source: URL, containerID: String, containerPath: String) async throws

    /// Copies a path out of a running container to the host (`copy <id>:<path> <dst>`).
    func copyFromContainer(
        containerID: String, containerPath: String, destination: URL
    ) async throws

    /// Lists a directory inside a running container (best-effort `exec <id> ls -la <path>`).
    func listContainerDirectory(id: String, path: String) async throws -> [ContainerFileEntry]

    // MARK: Images

    func listImages() async throws -> [ImageSummary]
    func inspectImage(reference: String) async throws -> Parsed<ImageSummary>
    func removeImage(reference: String) async throws

    /// Pulls an image (optionally constrained to a platform), streaming progress line-by-line.
    func pullImage(reference: String, platform: String?) -> AsyncThrowingStream<OutputLine, Error>

    /// Pushes an image to its registry, streaming progress line-by-line.
    func pushImage(reference: String, platform: String?) -> AsyncThrowingStream<OutputLine, Error>

    /// Saves one or more images as an OCI-compatible tar archive at `url`.
    func saveImage(references: [String], to url: URL, platform: String?) async throws

    /// Loads images from an OCI-compatible tar archive at `url`.
    func loadImage(from url: URL) async throws

    /// Creates a new reference (`target`) for an existing image (`source`).
    func tagImage(source: String, target: String) async throws

    /// Removes dangling images (or all unused when `all` is true); returns the CLI's
    /// best-effort reclaimed summary.
    func pruneImages(all: Bool) async throws -> PruneResult

    /// Builds an image from a Dockerfile/Containerfile, streaming progress line-by-line. The
    /// raw transcript is the source of truth — build logs are never collapsed or hidden.
    func buildImage(_ config: BuildConfiguration) -> AsyncThrowingStream<OutputLine, Error>

    // MARK: Volumes / networks / registries / machines / builder

    func listVolumes() async throws -> [VolumeSummary]
    func listNetworks() async throws -> [NetworkSummary]

    // MARK: Volume mutation / inspection (M8)

    /// Inspects one or more volumes, retaining the raw payload alongside the decoded rows.
    func inspectVolume(names: [String]) async throws -> Parsed<[VolumeSummary]>

    /// Creates a volume from a typed configuration.
    func createVolume(_ config: VolumeConfiguration) async throws

    /// Deletes one or more volumes by name (the CLI has no `--force`).
    func deleteVolumes(names: [String]) async throws

    /// Removes volumes with no container references; returns the reclaimed summary.
    func pruneVolumes() async throws -> PruneResult

    // MARK: Network mutation / inspection (M8)

    /// Inspects one or more networks, retaining the raw payload alongside the decoded rows.
    func inspectNetwork(names: [String]) async throws -> Parsed<[NetworkSummary]>

    /// Creates a network from a typed configuration.
    func createNetwork(_ config: NetworkConfiguration) async throws

    /// Deletes one or more networks by name (the CLI has no `--force`).
    func deleteNetworks(names: [String]) async throws

    /// Removes networks with no connections; returns the reclaimed summary.
    func pruneNetworks() async throws -> PruneResult

    // MARK: DNS (M8 — list only; create/delete are privileged via the sudo Terminal handoff)

    /// Lists local DNS domains (`system dns list`; no privilege required).
    func listDNSDomains() async throws -> [DNSDomainSummary]
    func listRegistries() async throws -> [RegistrySummary]
    func listMachines() async throws -> [MachineSummary]

    /// Returns the inspected summary of one machine (nil id → default machine).
    func inspectMachine(id: String?) async throws -> Parsed<MachineSummary>

    /// Creates a machine from a typed configuration; streams progress lines.
    func createMachine(_ config: MachineConfiguration) -> AsyncThrowingStream<OutputLine, Error>

    /// Applies settings to a machine (nil name → default machine).
    func setMachine(name: String?, settings: MachineSettings) async throws

    /// Marks one machine as the default, clearing the flag on all others.
    func setDefaultMachine(id: String) async throws

    /// Stops a running machine (nil id → default machine).
    func stopMachine(id: String?) async throws

    /// Permanently deletes a machine by id.
    func deleteMachine(id: String) async throws

    /// Fetches the tail of a machine's log (nil id → default machine).
    func fetchMachineLogs(id: String?, tail: Int?, boot: Bool) async throws -> [OutputLine]

    /// Follows a machine's log as a live stream (nil id → default machine).
    func followMachineLogs(id: String?, boot: Bool) -> AsyncThrowingStream<OutputLine, Error>

    func builderStatus() async throws -> BuilderStatus

    /// Logs in to a registry. The password is delivered out-of-band (never on argv) so it
    /// cannot leak through process listings, logs, or transcripts.
    func registryLogin(server: String, username: String?, password: String?) async throws

    /// Logs out from a registry, dropping its stored credential.
    func registryLogout(server: String) async throws

    /// Validates credentials against a registry without persisting a login in Capsule's
    /// model. (apple/container has no dry-run verb, so the adapter performs a real login.)
    func registryTest(server: String, username: String?, password: String?) async throws

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

    /// Convenience: pull for the host's default platform.
    public func pullImage(reference: String) -> AsyncThrowingStream<OutputLine, Error> {
        pullImage(reference: reference, platform: nil)
    }
}
