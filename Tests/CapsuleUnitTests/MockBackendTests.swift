//
//  MockBackendTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The in-memory backend is the substitute every higher layer (domain, previews, tests)
//  uses in place of the real CLI. These tests pin its seeded data, mutation, streaming,
//  and failure-injection behavior.

import CapsuleBackend
import XCTest

final class MockBackendTests: XCTestCase {
    func testReturnsSeededContainersAndImages() async throws {
        let backend = MockBackend()

        let containers = try await backend.listContainers(all: true)
        let images = try await backend.listImages()

        XCTAssertFalse(containers.isEmpty)
        XCTAssertFalse(images.isEmpty)
    }

    func testStopOptionsConstants() {
        XCTAssertEqual(StopOptions.default, StopOptions(timeout: nil, signal: nil))
        XCTAssertEqual(StopOptions.forced, StopOptions(timeout: 0, signal: nil))
    }

    func testStopRecordsOptions() async throws {
        let backend = MockBackend()
        try await backend.stopContainer(
            id: "a1b2c3d4", options: StopOptions(timeout: 3, signal: "TERM"))
        XCTAssertEqual(backend.lastStopOptions, StopOptions(timeout: 3, signal: "TERM"))
        let stopped = try await backend.listContainers(all: true).first { $0.id == "a1b2c3d4" }
        XCTAssertEqual(stopped?.state, "stopped")
    }

    func testStopConvenienceUsesDefault() async throws {
        let backend = MockBackend()
        try await backend.stopContainer(id: "a1b2c3d4")
        XCTAssertEqual(backend.lastStopOptions, .default)
    }

    func testStatsSnapshotReturnsSeededSamples() async throws {
        let backend = MockBackend(sampleStats: [
            ContainerStatsSample(id: "a1b2c3d4", cpuUsageUsec: 10)
        ])
        let samples = try await backend.containerStats(ids: ["a1b2c3d4"])
        XCTAssertEqual(samples.map(\.id), ["a1b2c3d4"])
    }

    func testStatsStreamEmitsThenFinishes() async throws {
        let backend = MockBackend(sampleStats: [
            ContainerStatsSample(id: "a1b2c3d4", cpuUsageUsec: 10)
        ])
        var batches = 0
        for try await batch in backend.streamContainerStats(
            ids: ["a1b2c3d4"], interval: .milliseconds(1))
        {
            XCTAssertEqual(batch.first?.id, "a1b2c3d4")
            batches += 1
            if batches >= 2 { break }
        }
        XCTAssertGreaterThanOrEqual(batches, 2)
    }

    func testKillRecordsSignalAndStops() async throws {
        let backend = MockBackend()
        try await backend.killContainer(id: "a1b2c3d4", signal: "TERM")
        XCTAssertEqual(backend.lastKillSignal, "TERM")
        let c = try await backend.listContainers(all: true).first { $0.id == "a1b2c3d4" }
        XCTAssertEqual(c?.state, "stopped")
    }

    func testPruneRemovesStoppedAndReportsReclaimed() async throws {
        let backend = MockBackend()
        let result = try await backend.pruneContainers()
        let all = try await backend.listContainers(all: true)
        XCTAssertFalse(all.contains { $0.state == "stopped" })
        XCTAssertNotNil(result.reclaimedDescription)
    }

    func testExportRecordsURL() async throws {
        let backend = MockBackend()
        let url = URL(fileURLWithPath: "/tmp/x.tar")
        try await backend.exportContainer(id: "a1b2c3d4", to: url)
        XCTAssertEqual(backend.lastExportURL, url)
    }

    func testSampleContainersAreRicherForBrowser() async throws {
        let all = try await MockBackend().listContainers(all: true)
        XCTAssertGreaterThanOrEqual(all.count, 3)
        XCTAssertTrue(all.contains { $0.state == "running" })
        XCTAssertTrue(all.contains { $0.state == "stopped" })
        XCTAssertTrue(all.allSatisfy { $0.createdAt != nil })
    }

    func testListContainersHonoursAllFlag() async throws {
        let backend = MockBackend(
            containers: [
                ContainerSummary(id: "1", name: "a", image: "alpine", state: "running"),
                ContainerSummary(id: "2", name: "b", image: "alpine", state: "stopped"),
            ]
        )

        let running = try await backend.listContainers(all: false)
        let all = try await backend.listContainers(all: true)

        XCTAssertEqual(running.map(\.id), ["1"])
        XCTAssertEqual(all.count, 2)
    }

    func testVersionAndCapabilitiesAreConsistent() async throws {
        let backend = MockBackend(version: BackendVersion(client: "1.0.0", server: "1.0.0"))

        let version = try await backend.version()
        let capabilities = try await backend.capabilities()
        XCTAssertEqual(version.client, "1.0.0")
        XCTAssertTrue(capabilities.supports(.containers))
    }

    func testStartAndStopMutateContainerState() async throws {
        let backend = MockBackend(
            containers: [ContainerSummary(id: "1", name: "a", image: "alpine", state: "stopped")]
        )

        try await backend.startContainer(id: "1")
        let afterStart = try await backend.listContainers(all: true)
        XCTAssertEqual(afterStart.first?.state, "running")

        try await backend.stopContainer(id: "1")
        let afterStop = try await backend.listContainers(all: true)
        XCTAssertEqual(afterStop.first?.state, "stopped")
    }

    func testRemoveContainerDropsItFromTheList() async throws {
        let backend = MockBackend(
            containers: [ContainerSummary(id: "1", name: "a", image: "alpine", state: "running")]
        )

        try await backend.removeContainer(id: "1", force: true)

        let remaining = try await backend.listContainers(all: true)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testInspectReturnsValueForKnownIdAndRawForUnknown() async throws {
        let backend = MockBackend(
            containers: [ContainerSummary(id: "1", name: "a", image: "alpine", state: "running")]
        )

        let known = try await backend.inspectContainer(id: "1")
        XCTAssertEqual(known.value?.id, "1")
        XCTAssertFalse(known.raw.isEmpty)

        let unknown = try await backend.inspectContainer(id: "nope")
        XCTAssertNil(unknown.value)
    }

    func testFollowLogsStreamsSeededLines() async throws {
        let backend = MockBackend(
            logLines: [
                OutputLine(source: .stdout, text: "line-1"),
                OutputLine(source: .stdout, text: "line-2"),
            ]
        )

        var received: [String] = []
        for try await line in backend.followLogs(container: "1") {
            received.append(line.text)
        }

        XCTAssertEqual(received, ["line-1", "line-2"])
    }

    func testSystemDefaultsToRunning() async throws {
        let backend = MockBackend()
        let status = try await backend.systemStatus()
        XCTAssertEqual(status, .running)
    }

    func testStopSystemThenStartSystemFlipsRunState() async throws {
        let backend = MockBackend()

        try await backend.stopSystem()
        let stopped = try await backend.systemStatus()
        XCTAssertEqual(stopped, .stopped)

        try await backend.startSystem()
        let running = try await backend.systemStatus()
        XCTAssertEqual(running, .running)
    }

    func testSystemStatusHonoursInjectedFailure() async throws {
        let backend = MockBackend()
        backend.failure = BackendError.nonZeroExit(
            command: "container system status", code: 1, stderr: "Connection refused")

        do {
            _ = try await backend.systemStatus()
            XCTFail("expected the injected failure to throw")
        } catch let BackendError.nonZeroExit(_, code, _) {
            XCTAssertEqual(code, 1)
        }
    }

    func testSystemRunStateSeedsFromInitializer() async throws {
        let backend = MockBackend(systemRunState: .stopped)
        let status = try await backend.systemStatus()
        XCTAssertEqual(status, .stopped)
    }

    // MARK: - Images (M6)

    func testSeededImagesCarryDigestAndCreationDate() async throws {
        let images = try await MockBackend().listImages()
        XCTAssertTrue(images.allSatisfy { $0.digest.hasPrefix("sha256:") })
        XCTAssertTrue(images.allSatisfy { $0.createdAt != nil })
    }

    func testTagAddsAReferenceAndRecordsArguments() async throws {
        let backend = MockBackend()
        try await backend.tagImage(
            source: "docker.io/library/alpine:latest", target: "alpine:pinned")
        XCTAssertEqual(backend.lastTag?.source, "docker.io/library/alpine:latest")
        XCTAssertEqual(backend.lastTag?.target, "alpine:pinned")
        let refs = try await backend.listImages().map(\.reference)
        XCTAssertTrue(refs.contains("alpine:pinned"))
    }

    func testRemoveImageDropsItFromTheList() async throws {
        let backend = MockBackend()
        try await backend.removeImage(reference: "docker.io/library/alpine:latest")
        let refs = try await backend.listImages().map(\.reference)
        XCTAssertFalse(refs.contains("docker.io/library/alpine:latest"))
    }

    func testPruneImagesRemovesDanglingAndReportsReclaimed() async throws {
        let backend = MockBackend(images: [
            ImageSummary(id: "1", reference: "<none>:<none>", sizeBytes: 10, digest: "sha256:1"),
            ImageSummary(id: "2", reference: "alpine:latest", sizeBytes: 20, digest: "sha256:2"),
        ])
        let result = try await backend.pruneImages(all: false)
        XCTAssertEqual(backend.prunedAll, false)
        let refs = try await backend.listImages().map(\.reference)
        XCTAssertEqual(refs, ["alpine:latest"], "only the dangling image is removed")
        XCTAssertNotNil(result.reclaimedDescription)
    }

    func testPruneImagesAllRemovesEverythingUnused() async throws {
        let backend = MockBackend(images: [
            ImageSummary(id: "1", reference: "<none>:<none>", sizeBytes: 10, digest: "sha256:1"),
            ImageSummary(id: "2", reference: "alpine:latest", sizeBytes: 20, digest: "sha256:2"),
        ])
        _ = try await backend.pruneImages(all: true)
        XCTAssertEqual(backend.prunedAll, true)
        let remaining = try await backend.listImages()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSaveAndLoadRecordTheirURLs() async throws {
        let backend = MockBackend()
        let out = URL(fileURLWithPath: "/tmp/a.tar")
        try await backend.saveImage(references: ["alpine:latest"], to: out, platform: nil)
        XCTAssertEqual(backend.lastSavedURL, out)
        let inp = URL(fileURLWithPath: "/tmp/b.tar")
        try await backend.loadImage(from: inp)
        XCTAssertEqual(backend.lastLoadedURL, inp)
    }

    func testPushImageStreamsLines() async throws {
        let backend = MockBackend(logLines: [OutputLine(source: .stdout, text: "pushing")])
        var received: [String] = []
        for try await line in backend.pushImage(reference: "ghcr.io/me/app:1", platform: nil) {
            received.append(line.text)
        }
        XCTAssertEqual(received, ["pushing"])
    }

    // MARK: - Registries (M6)

    func testLoginRecordsServerUsernameAndPasswordWithoutLeakingToArgv() async throws {
        let backend = MockBackend()
        try await backend.registryLogin(server: "ghcr.io", username: "me", password: "s3cret")
        XCTAssertEqual(backend.lastLogin?.server, "ghcr.io")
        XCTAssertEqual(backend.lastLogin?.username, "me")
        XCTAssertEqual(backend.lastLogin?.password, "s3cret")
        let servers = try await backend.listRegistries().map(\.server)
        XCTAssertTrue(servers.contains("ghcr.io"))
    }

    func testLogoutRemovesTheRegistry() async throws {
        let backend = MockBackend(registries: [RegistrySummary(server: "ghcr.io")])
        try await backend.registryLogout(server: "ghcr.io")
        XCTAssertEqual(backend.lastLogout, "ghcr.io")
        let remaining = try await backend.listRegistries()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testRegistryTestDoesNotPersistButRecordsTheAttempt() async throws {
        let backend = MockBackend()
        try await backend.registryTest(server: "ghcr.io", username: "me", password: "s3cret")
        XCTAssertEqual(backend.lastTest?.server, "ghcr.io")
        let registries = try await backend.listRegistries()
        XCTAssertTrue(registries.isEmpty, "a test must not add a persistent login in the mock")
    }

    func testImageOperationsHonourInjectedFailure() async throws {
        let backend = MockBackend()
        backend.failure = BackendError.nonZeroExit(
            command: "container image tag", code: 1, stderr: "boom")
        do {
            try await backend.tagImage(source: "a", target: "b")
            XCTFail("expected the injected failure to throw")
        } catch let BackendError.nonZeroExit(_, code, _) {
            XCTAssertEqual(code, 1)
        }
    }

    func testInjectedFailurePropagates() async throws {
        let backend = MockBackend()
        backend.failure = BackendError.nonZeroExit(
            command: "container list", code: 1, stderr: "boom")

        do {
            _ = try await backend.listContainers()
            XCTFail("expected the injected failure to throw")
        } catch let BackendError.nonZeroExit(_, code, stderr) {
            XCTAssertEqual(code, 1)
            XCTAssertEqual(stderr, "boom")
        }
    }

    // MARK: - M7 methods

    func testRunContainerRecordsConfigAndCreatesRunningContainer() async throws {
        let backend = MockBackend()
        let before = try await backend.listContainers(all: true).count
        let id = try await backend.runContainer(RunConfiguration(image: "nginx", name: "web"))
        XCTAssertEqual(backend.lastRunConfig?.image, "nginx")
        XCTAssertFalse(id.isEmpty)
        let after = try await backend.listContainers(all: true)
        XCTAssertEqual(after.count, before + 1)
        XCTAssertTrue(after.contains { $0.id == id && $0.state == "running" })
    }

    func testBuildImageRecordsConfigAndStreams() async throws {
        let backend = MockBackend()
        var lines = 0
        for try await _ in backend.buildImage(
            BuildConfiguration(contextDirectory: URL(fileURLWithPath: "/p"), tag: "t:1"))
        {
            lines += 1
        }
        XCTAssertEqual(backend.lastBuildConfig?.tag, "t:1")
        XCTAssertGreaterThan(lines, 0)
    }

    func testCopyRecordsEndpoints() async throws {
        let backend = MockBackend()
        try await backend.copyToContainer(
            source: URL(fileURLWithPath: "/h/f"), containerID: "c1", containerPath: "/app/f")
        XCTAssertEqual(backend.lastCopy?.direction, .toContainer)
        XCTAssertEqual(backend.lastCopy?.containerID, "c1")
        XCTAssertEqual(backend.lastCopy?.containerPath, "/app/f")

        try await backend.copyFromContainer(
            containerID: "c2", containerPath: "/var/log", destination: URL(fileURLWithPath: "/h/l"))
        XCTAssertEqual(backend.lastCopy?.direction, .fromContainer)
        XCTAssertEqual(backend.lastCopy?.containerID, "c2")
    }

    func testListContainerDirectoryReturnsSeededAndRecordsPath() async throws {
        let backend = MockBackend()
        let rows = try await backend.listContainerDirectory(id: "c1", path: "/etc")
        XCTAssertEqual(backend.lastListedDirectory?.path, "/etc")
        XCTAssertFalse(rows.isEmpty)
    }

    func testFetchLogsTails() async throws {
        let backend = MockBackend(
            logLines: [
                OutputLine(source: .stdout, text: "a"), OutputLine(source: .stdout, text: "b"),
                OutputLine(source: .stdout, text: "c"),
            ])
        let tailed = try await backend.fetchLogs(container: "c1", tail: 2, boot: false)
        XCTAssertEqual(tailed.map(\.text), ["b", "c"])
    }

    func testM7MethodsHonorInjectedFailure() async {
        let backend = MockBackend()
        backend.failure = BackendError.nonZeroExit(command: "x", code: 1, stderr: "boom")
        do {
            _ = try await backend.runContainer(RunConfiguration(image: "nginx"))
            XCTFail("expected failure")
        } catch {}
    }

    // MARK: - Volumes / networks / DNS (M8)

    func testCreateVolumeRecordsConfigAndAppendsToList() async throws {
        let backend = MockBackend()
        try await backend.createVolume(VolumeConfiguration(name: "data", size: "1G"))
        XCTAssertEqual(backend.lastCreatedVolume?.name, "data")
        XCTAssertEqual(backend.lastCreatedVolume?.size, "1G")
        let names = try await backend.listVolumes().map(\.name)
        XCTAssertTrue(names.contains("data"))
    }

    func testDeleteVolumesRemovesAndRecords() async throws {
        let backend = MockBackend(volumes: [
            VolumeSummary(name: "data"), VolumeSummary(name: "keep"),
        ])
        try await backend.deleteVolumes(names: ["data"])
        XCTAssertEqual(backend.lastDeletedVolumeNames, ["data"])
        let names = try await backend.listVolumes().map(\.name)
        XCTAssertEqual(names, ["keep"])
    }

    func testPruneVolumesEmptiesAndReportsReclaimed() async throws {
        let backend = MockBackend(volumes: [VolumeSummary(name: "a"), VolumeSummary(name: "b")])
        XCTAssertFalse(backend.didPruneVolumes)
        let result = try await backend.pruneVolumes()
        XCTAssertTrue(backend.didPruneVolumes)
        XCTAssertNotNil(result.reclaimedDescription)
        let remaining = try await backend.listVolumes()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testInspectVolumeReturnsMatchesAndRaw() async throws {
        let backend = MockBackend(volumes: [VolumeSummary(name: "data"), VolumeSummary(name: "x")])
        let parsed = try await backend.inspectVolume(names: ["data"])
        XCTAssertEqual(parsed.value?.map(\.name), ["data"])
        XCTAssertFalse(parsed.raw.isEmpty)
    }

    func testCreateNetworkRecordsConfigAndAppends() async throws {
        let backend = MockBackend()
        try await backend.createNetwork(
            NetworkConfiguration(name: "app-net", subnet: "10.0.0.0/24"))
        XCTAssertEqual(backend.lastCreatedNetwork?.name, "app-net")
        let names = try await backend.listNetworks().map(\.name)
        XCTAssertTrue(names.contains("app-net"))
    }

    func testDeleteNetworksRemovesAndRecords() async throws {
        let backend = MockBackend(networks: [
            NetworkSummary(id: "app-net", name: "app-net"),
            NetworkSummary(id: "default", name: "default", isBuiltin: true),
        ])
        try await backend.deleteNetworks(names: ["app-net"])
        XCTAssertEqual(backend.lastDeletedNetworkNames, ["app-net"])
        let names = try await backend.listNetworks().map(\.name)
        XCTAssertEqual(names, ["default"])
    }

    func testPruneNetworksExcludesBuiltins() async throws {
        let backend = MockBackend(networks: [
            NetworkSummary(id: "app-net", name: "app-net"),
            NetworkSummary(id: "default", name: "default", isBuiltin: true),
        ])
        XCTAssertFalse(backend.didPruneNetworks)
        let result = try await backend.pruneNetworks()
        XCTAssertTrue(backend.didPruneNetworks)
        XCTAssertNotNil(result.reclaimedDescription)
        let names = try await backend.listNetworks().map(\.name)
        XCTAssertEqual(names, ["default"], "builtin networks survive prune")
    }

    func testListDNSDomainsReturnsSeeded() async throws {
        let backend = MockBackend(dnsDomains: [DNSDomainSummary(domain: "capsule.test")])
        let domains = try await backend.listDNSDomains()
        XCTAssertEqual(domains.map(\.domain), ["capsule.test"])
    }

    func testVolumeNetworkOpsHonourInjectedFailure() async {
        let backend = MockBackend()
        backend.failure = BackendError.nonZeroExit(command: "x", code: 1, stderr: "boom")
        do {
            try await backend.createVolume(VolumeConfiguration(name: "data"))
            XCTFail("expected the injected failure to throw")
        } catch let BackendError.nonZeroExit(_, code, _) {
            XCTAssertEqual(code, 1)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
