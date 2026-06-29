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
    private var dnsDomains: [DNSDomainSummary]
    private var versionValue: BackendVersion
    private var builder: BuilderStatus
    private var logLines: [OutputLine]
    private var systemRunStateValue: SystemRunState
    private var sampleStats: [ContainerStatsSample]
    public var componentVersions: [ComponentVersion] = [
        ComponentVersion(
            appName: "container", version: "1.0.0",
            buildType: "release", commit: "ee848e3"),
        ComponentVersion(
            appName: "container-apiserver",
            version: "container-apiserver version 1.0.0 (build: release, commit: ee848e3)",
            buildType: "release", commit: "ee848e3"),
    ]
    public var diskUsage = StorageUsage(
        images: CategoryUsage(
            total: 4, active: 1, sizeInBytes: 1_302_421_504, reclaimable: 974_934_016),
        containers: CategoryUsage(
            total: 1, active: 0, sizeInBytes: 454_991_872, reclaimable: 454_991_872),
        volumes: CategoryUsage(total: 0, active: 0, sizeInBytes: 0, reclaimable: 0))
    public var propertiesTOML = """
        [build]
        cpus = 2
        memory = "2048mb"
        rosetta = true

        [kernel]
        binaryPath = "opt/kata/share/kata-containers/vmlinux-6.18.15-186"
        url = "https://github.com/kata-containers/kata-containers/releases/download/3.28.0/kata-static-3.28.0-arm64.tar.zst"

        [machine]
        cpus = 5
        homeMount = "rw"
        memory = "16gb"
        """
    public var properties = SystemProperties(sections: [
        PropertySection(
            name: "build",
            entries: [
                .init(key: "cpus", value: "2"),
                .init(key: "memory", value: "2048mb"),
                .init(key: "rosetta", value: "true"),
            ]),
        PropertySection(
            name: "kernel",
            entries: [
                .init(
                    key: "binaryPath", value: "opt/kata/share/kata-containers/vmlinux-6.18.15-186"),
                .init(
                    key: "url",
                    value: "https://github.com/kata-containers/…/kata-static-3.28.0-arm64.tar.zst"),
            ]),
    ])

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
    /// The signal passed to the most recent `killContainer` call.
    public private(set) var lastKillSignal: String?
    /// The URL passed to the most recent `exportContainer` call.
    public private(set) var lastExportURL: URL?
    /// The source/target of the most recent `tagImage` call.
    public private(set) var lastTag: (source: String, target: String)?
    /// The URL passed to the most recent `saveImage` call.
    public private(set) var lastSavedURL: URL?
    /// The URL passed to the most recent `loadImage` call.
    public private(set) var lastLoadedURL: URL?
    /// The `all` flag passed to the most recent `pruneImages` call.
    public private(set) var prunedAll: Bool?
    /// The server/username/password of the most recent `registryLogin` call.
    public private(set) var lastLogin: (server: String, username: String?, password: String?)?
    /// The server/username/password of the most recent `registryTest` call.
    public private(set) var lastTest: (server: String, username: String?, password: String?)?
    /// The server passed to the most recent `registryLogout` call.
    public private(set) var lastLogout: String?
    /// How many times `containerStats` has been invoked (for stream-teardown tests).
    public private(set) var statsCallCount = 0
    /// How many `followLogs` streams have terminated (incl. via cancellation).
    public private(set) var logStreamTerminations = 0
    /// The configuration of the most recent `runContainer` call.
    public private(set) var lastRunConfig: RunConfiguration?
    /// The configuration of the most recent `buildImage` call.
    public private(set) var lastBuildConfig: BuildConfiguration?
    /// The direction/endpoints of the most recent copy call.
    public private(set) var lastCopy:
        (direction: CopyDirectionTag, hostURL: URL, containerID: String, containerPath: String)?
    /// The id/path of the most recent `listContainerDirectory` call.
    public private(set) var lastListedDirectory: (id: String, path: String)?
    /// Seeded directory entries returned by `listContainerDirectory`.
    public var containerFiles: [ContainerFileEntry] = MockBackend.sampleContainerFiles
    /// The configuration of the most recent `createVolume` call.
    public private(set) var lastCreatedVolume: VolumeConfiguration?
    /// The names of the most recent `deleteVolumes` call.
    public private(set) var lastDeletedVolumeNames: [String]?
    /// Whether `pruneVolumes` has been invoked.
    public private(set) var didPruneVolumes = false
    /// The configuration of the most recent `createNetwork` call.
    public private(set) var lastCreatedNetwork: NetworkConfiguration?
    /// The names of the most recent `deleteNetworks` call.
    public private(set) var lastDeletedNetworkNames: [String]?
    /// Whether `pruneNetworks` has been invoked.
    public private(set) var didPruneNetworks = false

    /// The configuration of the most recent `createMachine` call.
    public private(set) var lastCreatedMachine: MachineConfiguration?
    /// The (name, settings) of the most recent `setMachine` call.
    public private(set) var lastMachineSettings: (name: String?, settings: MachineSettings)?
    /// The id of the most recent `setDefaultMachine` call.
    public private(set) var lastSetDefaultID: String?
    /// The id of the most recent `stopMachine` call.
    public private(set) var lastStoppedMachine: String?
    /// The id of the most recent `deleteMachine` call.
    public private(set) var lastDeletedMachine: String?

    /// The configuration of the most recent `setKernel` call.
    public private(set) var lastKernelConfiguration: KernelConfiguration?

    /// Which way a recorded copy went (the mock has no real filesystem).
    public enum CopyDirectionTag: Sendable, Equatable { case toContainer, fromContainer }

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
        sampleStats: [ContainerStatsSample] = MockBackend.sampleStatsDefault,
        dnsDomains: [DNSDomainSummary] = []
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
        self.dnsDomains = dnsDomains
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

    public func systemDiskUsage() async throws -> StorageUsage { try withState { $0.diskUsage } }
    public func systemComponentVersions() async throws -> [ComponentVersion] {
        try withState { $0.componentVersions }
    }
    public func systemProperties() async throws -> SystemProperties {
        try withState { $0.properties }
    }
    public func systemPropertiesTOML() async throws -> String {
        try withState { $0.propertiesTOML }
    }

    public var systemLogLines: [OutputLine] = [
        OutputLine(source: .stdout, text: "apiserver: started"),
        OutputLine(source: .stdout, text: "apiserver: listening"),
    ]

    public func fetchSystemLogs(last: String) async throws -> [OutputLine] { systemLogLines }

    public func followSystemLogs() -> AsyncThrowingStream<OutputLine, Error> {
        AsyncThrowingStream { continuation in
            for line in systemLogLines { continuation.yield(line) }
            continuation.finish()
        }
    }

    public func setKernel(_ config: KernelConfiguration) -> AsyncThrowingStream<OutputLine, Error> {
        lastKernelConfiguration = config
        return AsyncThrowingStream { continuation in
            continuation.yield(OutputLine(source: .stdout, text: "Installing kernel…"))
            continuation.yield(OutputLine(source: .stdout, text: "Done."))
            continuation.finish()
        }
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

    public func killContainer(id: String, signal: String?) async throws {
        try withState { state in
            state.lastKillSignal = signal
            state.mutateContainer(id) {
                $0.state = "stopped"
                $0.ip = nil
            }
        }
    }

    public func pruneContainers() async throws -> PruneResult {
        try withState { state in
            let removed = state.containers.filter { $0.state != "running" }.count
            state.containers.removeAll { $0.state != "running" }
            return PruneResult(reclaimedDescription: "Reclaimed \(removed) item(s).", raw: "")
        }
    }

    public func exportContainer(id: String, to url: URL) async throws {
        try withState { state in state.lastExportURL = url }
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

    public func fetchLogs(container id: String, tail: Int?, boot: Bool) async throws -> [OutputLine]
    {
        try withState { state in
            let lines = state.logLines
            if let tail, tail < lines.count { return Array(lines.suffix(tail)) }
            return lines
        }
    }

    public func runContainer(_ config: RunConfiguration) async throws -> String {
        try withState { state in
            state.lastRunConfig = config
            let id = "mock-\(state.containers.count + 1)"
            state.containers.append(
                ContainerSummary(
                    id: id, name: config.name ?? id, image: config.image, state: "running",
                    ip: "192.168.64.99", createdAt: "2026-06-29T00:00:00Z"))
            return id
        }
    }

    public func copyToContainer(
        source: URL, containerID: String, containerPath: String
    ) async throws {
        try withState { state in
            state.lastCopy = (.toContainer, source, containerID, containerPath)
        }
    }

    public func copyFromContainer(
        containerID: String, containerPath: String, destination: URL
    ) async throws {
        try withState { state in
            state.lastCopy = (.fromContainer, destination, containerID, containerPath)
        }
    }

    public func listContainerDirectory(
        id: String, path: String
    ) async throws -> [ContainerFileEntry] {
        try withState { state in
            state.lastListedDirectory = (id, path)
            return state.containerFiles
        }
    }

    // MARK: - Images

    public func listImages() async throws -> [ImageSummary] {
        try withState { $0.images }
    }

    public func inspectImage(reference: String) async throws -> Parsed<ImageSummary> {
        try withState { state in
            // The CLI accepts a reference or an id; dangling images are addressed by id.
            let match = state.images.first { $0.reference == reference || $0.id == reference }
            return Parsed(value: match, raw: match.map { "\($0)" } ?? "")
        }
    }

    public func removeImage(reference: String) async throws {
        try withState { state in
            state.images.removeAll { $0.reference == reference }
        }
    }

    public func pullImage(
        reference: String, platform: String?
    ) -> AsyncThrowingStream<OutputLine, Error> {
        seededStream()
    }

    public func pushImage(
        reference: String, platform: String?
    ) -> AsyncThrowingStream<OutputLine, Error> {
        seededStream()
    }

    public func buildImage(_ config: BuildConfiguration) -> AsyncThrowingStream<OutputLine, Error> {
        lock.lock()
        lastBuildConfig = config
        lock.unlock()
        return seededStream()
    }

    public func saveImage(references: [String], to url: URL, platform: String?) async throws {
        try withState { state in state.lastSavedURL = url }
    }

    public func loadImage(from url: URL) async throws {
        try withState { state in state.lastLoadedURL = url }
    }

    public func tagImage(source: String, target: String) async throws {
        try withState { state in
            state.lastTag = (source: source, target: target)
            if let original = state.images.first(where: { $0.reference == source }) {
                state.images.append(
                    ImageSummary(
                        id: original.id, reference: target, sizeBytes: original.sizeBytes,
                        digest: original.digest, createdAt: original.createdAt))
            }
        }
    }

    public func pruneImages(all: Bool) async throws -> PruneResult {
        try withState { state in
            state.prunedAll = all
            let removed: Int
            if all {
                removed = state.images.count
                state.images.removeAll()
            } else {
                let dangling = state.images.filter { $0.reference.contains("<none>") }
                removed = dangling.count
                state.images.removeAll { $0.reference.contains("<none>") }
            }
            return PruneResult(reclaimedDescription: "Reclaimed \(removed) image(s).", raw: "")
        }
    }

    // MARK: - Volumes / networks / registries / machines / builder

    public func listVolumes() async throws -> [VolumeSummary] { try withState { $0.volumes } }
    public func listNetworks() async throws -> [NetworkSummary] { try withState { $0.networks } }

    public func inspectVolume(names: [String]) async throws -> Parsed<[VolumeSummary]> {
        try withState { state in
            let matches = state.volumes.filter { names.contains($0.name) }
            return Parsed(value: matches, raw: "\(matches)")
        }
    }

    public func createVolume(_ config: VolumeConfiguration) async throws {
        try withState { state in
            state.lastCreatedVolume = config
            if !state.volumes.contains(where: { $0.name == config.name }) {
                state.volumes.append(VolumeSummary(name: config.name))
            }
        }
    }

    public func deleteVolumes(names: [String]) async throws {
        try withState { state in
            state.lastDeletedVolumeNames = names
            state.volumes.removeAll { names.contains($0.name) }
        }
    }

    public func pruneVolumes() async throws -> PruneResult {
        try withState { state in
            let removed = state.volumes.count
            state.didPruneVolumes = true
            state.volumes.removeAll()
            return PruneResult(
                reclaimedDescription: "Reclaimed \(removed) volume(s).", raw: "")
        }
    }

    public func inspectNetwork(names: [String]) async throws -> Parsed<[NetworkSummary]> {
        try withState { state in
            let matches = state.networks.filter { names.contains($0.name) }
            return Parsed(value: matches, raw: "\(matches)")
        }
    }

    public func createNetwork(_ config: NetworkConfiguration) async throws {
        try withState { state in
            state.lastCreatedNetwork = config
            if !state.networks.contains(where: { $0.name == config.name }) {
                state.networks.append(
                    NetworkSummary(id: config.name, name: config.name, subnet: config.subnet))
            }
        }
    }

    public func deleteNetworks(names: [String]) async throws {
        try withState { state in
            state.lastDeletedNetworkNames = names
            state.networks.removeAll { names.contains($0.name) }
        }
    }

    public func pruneNetworks() async throws -> PruneResult {
        try withState { state in
            let removable = state.networks.filter { !$0.isBuiltin }.count
            state.didPruneNetworks = true
            state.networks.removeAll { !$0.isBuiltin }
            return PruneResult(
                reclaimedDescription: "Reclaimed \(removable) network(s).", raw: "")
        }
    }

    public func listDNSDomains() async throws -> [DNSDomainSummary] {
        try withState { $0.dnsDomains }
    }

    public func listRegistries() async throws -> [RegistrySummary] {
        try withState { $0.registries }
    }

    public func registryLogin(server: String, username: String?, password: String?) async throws {
        try withState { state in
            state.lastLogin = (server: server, username: username, password: password)
            if !state.registries.contains(where: { $0.server == server }) {
                state.registries.append(RegistrySummary(server: server))
            }
        }
    }

    public func registryLogout(server: String) async throws {
        try withState { state in
            state.lastLogout = server
            state.registries.removeAll { $0.server == server }
        }
    }

    public func registryTest(server: String, username: String?, password: String?) async throws {
        // A test validates credentials but, unlike login, does not persist a registry entry.
        try withState { state in
            state.lastTest = (server: server, username: username, password: password)
        }
    }
    public func listMachines() async throws -> [MachineSummary] { try withState { $0.machines } }

    public func inspectMachine(id: String?) async throws -> Parsed<MachineSummary> {
        try withState { state in
            let match =
                id.flatMap { wanted in state.machines.first { $0.name == wanted } }
                ?? state.machines.first { $0.isDefault } ?? state.machines.first
            return Parsed(value: match, raw: match.map { "\($0)" } ?? "")
        }
    }

    public func createMachine(
        _ config: MachineConfiguration
    )
        -> AsyncThrowingStream<OutputLine, Error>
    {
        lock.lock()
        lastCreatedMachine = config
        if !machines.contains(where: { $0.name == (config.name ?? config.image) }) {
            if config.setDefault { for i in machines.indices { machines[i].isDefault = false } }
            machines.append(
                MachineSummary(
                    name: config.name ?? config.image,
                    state: config.noBoot ? "stopped" : "running",
                    cpus: config.cpus, memory: config.memory,
                    isDefault: config.setDefault, homeMount: config.homeMount))
        }
        lock.unlock()
        return seededStream()
    }

    public func setMachine(name: String?, settings: MachineSettings) async throws {
        try withState { state in
            state.lastMachineSettings = (name, settings)
            let target = name ?? state.machines.first { $0.isDefault }?.name
            guard let target, let idx = state.machines.firstIndex(where: { $0.name == target })
            else { return }
            if let c = settings.cpus { state.machines[idx].cpus = c }
            if let m = settings.memory { state.machines[idx].memory = m }
            if let h = settings.homeMount { state.machines[idx].homeMount = h }
        }
    }

    public func setDefaultMachine(id: String) async throws {
        try withState { state in
            state.lastSetDefaultID = id
            for i in state.machines.indices {
                state.machines[i].isDefault = (state.machines[i].name == id)
            }
        }
    }

    public func stopMachine(id: String?) async throws {
        try withState { state in
            let target = id ?? state.machines.first { $0.isDefault }?.name
            state.lastStoppedMachine = target
            if let target, let idx = state.machines.firstIndex(where: { $0.name == target }) {
                state.machines[idx].state = "stopped"
            }
        }
    }

    public func deleteMachine(id: String) async throws {
        try withState { state in
            state.lastDeletedMachine = id
            state.machines.removeAll { $0.name == id }
        }
    }

    public func fetchMachineLogs(id: String?, tail: Int?, boot: Bool) async throws -> [OutputLine] {
        try withState { state in
            let lines = state.logLines
            if let tail, tail < lines.count { return Array(lines.suffix(tail)) }
            return lines
        }
    }

    public func followMachineLogs(id: String?, boot: Bool) -> AsyncThrowingStream<OutputLine, Error>
    {
        seededStream()
    }

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
        ImageSummary(
            id: "28bd5fe8", reference: "docker.io/library/alpine:latest", sizeBytes: 9218,
            digest: "sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b",
            createdAt: "2026-06-16T00:00:15Z"),
        ImageSummary(
            id: "9c7a4f10", reference: "docker.io/library/postgres:16", sizeBytes: 138_412_032,
            digest: "sha256:9c7a4f10e6d2b3a1c5f8e0d7b6a4938271605f4e3d2c1b0a9f8e7d6c5b4a3920",
            createdAt: "2026-06-10T08:30:00Z"),
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

    public static let sampleMachines: [MachineSummary] = [
        MachineSummary(
            name: "default", state: "running", createdAt: "2026-06-20T09:15:00Z",
            ipAddress: "192.168.66.2", cpus: 4, memory: "8G", disk: "20G", isDefault: true,
            homeMount: "rw"),
        MachineSummary(
            name: "builder", state: "stopped", createdAt: "2026-06-18T14:02:30Z",
            cpus: 2, memory: "4G", disk: "20G", isDefault: false, homeMount: "rw"),
    ]

    public static let sampleLogLines: [OutputLine] = [
        OutputLine(source: .stdout, text: "starting"),
        OutputLine(source: .stdout, text: "ready"),
    ]

    public static let sampleContainerFiles: [ContainerFileEntry] = [
        ContainerFileEntry(name: "bin", isDirectory: true, size: 4096, mode: "drwxr-xr-x"),
        ContainerFileEntry(name: "etc", isDirectory: true, size: 4096, mode: "drwxr-xr-x"),
        ContainerFileEntry(name: ".bashrc", isDirectory: false, size: 220, mode: "-rw-r--r--"),
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
