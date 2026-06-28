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
}
