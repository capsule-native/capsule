//
//  MockBackend.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  An in-memory `ContainerBackend` for unit tests and SwiftUI previews. It serves seeded
//  data, mutates it on lifecycle calls, streams seeded log lines, and can be told to fail
//  — so the whole stack above the port can be exercised without the `container` CLI.

import Foundation

public final class MockBackend: ContainerBackend, @unchecked Sendable {
    private let lock = NSLock()

    private var containers: [ContainerSummary]
    private var images: [ImageSummary]
    private var volumes: [VolumeSummary]
    private var networks: [NetworkSummary]
    private var registries: [RegistrySummary]
    private var machines: [MachineSummary]
    private var versionValue: BackendVersion
    private var builder: BuilderStatus
    private var logLines: [OutputLine]
    private var systemRunStateValue: SystemRunState
    private var sampleStats: [ContainerStatsSample]

    /// When set, every `throws` command throws this instead of returning.
    public var failure: BackendError?
    /// When set, `startContainer` throws this (independent of `failure`).
    public var startFailure: BackendError?
    /// When set, `stopContainer` awaits this delay before mutating — lets tests drive the
    /// hang watchdog deterministically.
    public var stopDelay: Duration?
    /// When true, `followLogs` yields the seeded lines then stays open (never finishes) so
    /// tests can exercise attach single-flight cancellation.
    public var neverEndingLogStream = false
    /// The options passed to the most recent `stopContainer` call.
    public private(set) var lastStopOptions: StopOptions?
    /// How many times `containerStats` has been invoked (for stream-teardown tests).
    public private(set) var statsCallCount = 0
    /// How many `followLogs` streams have terminated (incl. via cancellation).
    public private(set) var logStreamTerminations = 0

    public init(
        containers: [ContainerSummary] = MockBackend.sampleContainers,
        images: [ImageSummary] = MockBackend.sampleImages,
        volumes: [VolumeSummary] = [],
        networks: [NetworkSummary] = MockBackend.sampleNetworks,
        registries: [RegistrySummary] = [],
        machines: [MachineSummary] = [],
        version: BackendVersion = BackendVersion(client: "1.0.0", server: "1.0.0"),
        builder: BuilderStatus = BuilderStatus(isRunning: false),
        logLines: [OutputLine] = MockBackend.sampleLogLines,
        systemRunState: SystemRunState = .running,
        sampleStats: [ContainerStatsSample] = MockBackend.sampleStatsDefault
    ) {
        self.containers = containers
        self.images = images
        self.volumes = volumes
        self.networks = networks
        self.registries = registries
        self.machines = machines
        self.versionValue = version
        self.builder = builder
        self.logLines = logLines
        self.systemRunStateValue = systemRunState
        self.sampleStats = sampleStats
    }

    // MARK: - System & capabilities

    public func version() async throws -> BackendVersion {
        try withState { _ in versionValue }
    }

    public func systemStatus() async throws -> SystemRunState {
        try withState { $0.systemRunStateValue }
    }

    public func startSystem() async throws {
        try withState { $0.systemRunStateValue = .running }
    }

    public func stopSystem() async throws {
        try withState { $0.systemRunStateValue = .stopped }
    }

    public func capabilities() async throws -> BackendCapabilities {
        BackendCapabilities.derive(from: try await version())
    }

    // MARK: - Containers

    public func listContainers(all: Bool) async throws -> [ContainerSummary] {
        try withState { state in
            all ? state.containers : state.containers.filter { $0.state == "running" }
        }
    }

    public func inspectContainer(id: String) async throws -> Parsed<ContainerSummary> {
        try withState { state in
            let match = state.containers.first { $0.id == id }
            return Parsed(value: match, raw: match.map { "\($0)" } ?? "")
        }
    }

    public func startContainer(id: String) async throws {
        if let startFailure { throw startFailure }
        try withState { state in
            state.mutateContainer(id) { $0.state = "running" }
        }
    }

    public func stopContainer(id: String, options: StopOptions) async throws {
        if let stopDelay { try? await Task.sleep(for: stopDelay) }
        try withState { state in
            state.lastStopOptions = options
            state.mutateContainer(id) {
                $0.state = "stopped"
                $0.ip = nil
            }
        }
    }

    public func containerStats(ids: [String]) async throws -> [ContainerStatsSample] {
        try withState { state in
            state.statsCallCount += 1
            return ids.isEmpty
                ? state.sampleStats : state.sampleStats.filter { ids.contains($0.id) }
        }
    }

    public func streamContainerStats(
        ids: [String], interval: Duration
    )
        -> AsyncThrowingStream<[ContainerStatsSample], Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        let batch = try await containerStats(ids: ids)
                        if Task.isCancelled { break }
                        continuation.yield(batch)
                        try await Task.sleep(for: interval)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func removeContainer(id: String, force: Bool) async throws {
        try withState { state in
            state.containers.removeAll { $0.id == id }
        }
    }

    public func followLogs(container id: String) -> AsyncThrowingStream<OutputLine, Error> {
        guard neverEndingLogStream else { return seededStream() }
        lock.lock()
        let lines = logLines
        lock.unlock()
        return AsyncThrowingStream { continuation in
            for line in lines { continuation.yield(line) }
            continuation.onTermination = { [weak self] _ in self?.incrementLogTerminations() }
            // Deliberately never finished: stays open until the consumer cancels.
        }
    }

    private func incrementLogTerminations() {
        lock.lock()
        defer { lock.unlock() }
        logStreamTerminations += 1
    }

    // MARK: - Images

    public func listImages() async throws -> [ImageSummary] {
        try withState { $0.images }
    }

    public func inspectImage(reference: String) async throws -> Parsed<ImageSummary> {
        try withState { state in
            let match = state.images.first { $0.reference == reference }
            return Parsed(value: match, raw: match.map { "\($0)" } ?? "")
        }
    }

    public func removeImage(reference: String) async throws {
        try withState { state in
            state.images.removeAll { $0.reference == reference }
        }
    }

    public func pullImage(reference: String) -> AsyncThrowingStream<OutputLine, Error> {
        seededStream()
    }

    // MARK: - Volumes / networks / registries / machines / builder

    public func listVolumes() async throws -> [VolumeSummary] { try withState { $0.volumes } }
    public func listNetworks() async throws -> [NetworkSummary] { try withState { $0.networks } }
    public func listRegistries() async throws -> [RegistrySummary] {
        try withState { $0.registries }
    }
    public func listMachines() async throws -> [MachineSummary] { try withState { $0.machines } }
    public func builderStatus() async throws -> BuilderStatus { try withState { $0.builder } }

    // MARK: - Escape hatches

    public func runRaw(_ arguments: [String]) async throws -> RawCommandOutput {
        RawCommandOutput(exitCode: 0, stdout: "", stderr: "")
    }

    public func streamRaw(_ arguments: [String]) -> AsyncThrowingStream<OutputLine, Error> {
        seededStream()
    }

    // MARK: - Internals

    /// Runs `body` under the lock, throwing the injected `failure` first if present.
    private func withState<T>(_ body: (MockBackend) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        if let failure { throw failure }
        return try body(self)
    }

    private func mutateContainer(_ id: String, _ change: (inout ContainerSummary) -> Void) {
        guard let index = containers.firstIndex(where: { $0.id == id }) else { return }
        change(&containers[index])
    }

    private func seededStream() -> AsyncThrowingStream<OutputLine, Error> {
        lock.lock()
        let lines = logLines
        lock.unlock()
        return AsyncThrowingStream { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        }
    }
}

extension MockBackend {
    public static let sampleContainers: [ContainerSummary] = [
        ContainerSummary(
            id: "a1b2c3d4",
            name: "web",
            image: "docker.io/library/alpine:latest",
            state: "running",
            ip: "192.168.64.3",
            createdAt: "2026-06-20T09:15:00Z"
        ),
        ContainerSummary(
            id: "e5f6a7b8",
            name: "db",
            image: "docker.io/library/postgres:16",
            state: "stopped",
            createdAt: "2026-06-18T14:02:30Z"
        ),
        ContainerSummary(
            id: "0c1d2e3f",
            name: "cache",
            image: "docker.io/library/redis:7",
            state: "running",
            ip: "192.168.64.4",
            createdAt: "2026-06-21T11:47:10Z"
        ),
    ]

    public static let sampleImages: [ImageSummary] = [
        ImageSummary(id: "28bd5fe8", reference: "docker.io/library/alpine:latest", sizeBytes: 9218),
        ImageSummary(
            id: "9c7a4f10", reference: "docker.io/library/postgres:16", sizeBytes: 138_412_032),
    ]

    public static let sampleNetworks: [NetworkSummary] = [
        NetworkSummary(
            id: "default",
            name: "default",
            mode: "nat",
            gateway: "192.168.64.1",
            subnet: "192.168.64.0/24"
        )
    ]

    public static let sampleLogLines: [OutputLine] = [
        OutputLine(source: .stdout, text: "starting"),
        OutputLine(source: .stdout, text: "ready"),
    ]

    public static let sampleStatsDefault: [ContainerStatsSample] = [
        ContainerStatsSample(
            id: "a1b2c3d4", cpuUsageUsec: 1_000_000, memoryUsageBytes: 64_000_000,
            memoryLimitBytes: 512_000_000, networkRxBytes: 1024, networkTxBytes: 2048,
            numProcesses: 3),
        ContainerStatsSample(
            id: "0c1d2e3f", cpuUsageUsec: 500_000, memoryUsageBytes: 32_000_000,
            memoryLimitBytes: 256_000_000, numProcesses: 1),
    ]
}
