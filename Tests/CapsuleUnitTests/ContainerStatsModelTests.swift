//
//  ContainerStatsModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class ContainerStatsModelTests: XCTestCase {
    func testSnapshotPopulatesMetrics() async {
        let backend = MockBackend(sampleStats: [
            ContainerStatsSample(
                id: "a1b2c3d4", cpuUsageUsec: 10, memoryUsageBytes: 5, memoryLimitBytes: 10)
        ])
        let model = ContainerStatsModel(backend: backend)
        await model.snapshot(ids: ["a1b2c3d4"])
        XCTAssertEqual(model.metrics["a1b2c3d4"]?.memoryPercent ?? -1, 50, accuracy: 0.001)
    }

    func testEmptyIdsDoesNotCallBackend() async {
        let backend = MockBackend()
        backend.failure = .nonZeroExit(command: "stats", code: 1, stderr: "should not be called")
        let model = ContainerStatsModel(backend: backend)
        await model.snapshot(ids: [])  // must early-return, not throw/populate
        XCTAssertTrue(model.metrics.isEmpty)
    }

    func testCPUPercentFromConsecutiveSamples() {
        let model = ContainerStatsModel(backend: MockBackend())
        let m1 = model.ingest(ContainerStatsSample(id: "c", cpuUsageUsec: 0), at: 0)
        XCTAssertNil(m1.cpuPercent)  // no prior sample
        // +1_000_000 usec over 1 s = 100% of one core.
        let m2 = model.ingest(ContainerStatsSample(id: "c", cpuUsageUsec: 1_000_000), at: 1)
        XCTAssertEqual(m2.cpuPercent ?? -1, 100, accuracy: 0.5)
    }

    func testEpsilonGuardHoldsPriorCPUWhenElapsedTooSmall() {
        let model = ContainerStatsModel(backend: MockBackend())
        _ = model.ingest(ContainerStatsSample(id: "c", cpuUsageUsec: 0), at: 0)
        let m2 = model.ingest(ContainerStatsSample(id: "c", cpuUsageUsec: 1_000_000), at: 1)
        // Third sample at the same instant (~0 elapsed) must not divide by ~0.
        let m3 = model.ingest(ContainerStatsSample(id: "c", cpuUsageUsec: 2_000_000), at: 1)
        XCTAssertEqual(m3.cpuPercent, m2.cpuPercent)  // prior value held
    }

    func testStreamingStopsPollingAfterStop() async {
        let backend = MockBackend(sampleStats: [
            ContainerStatsSample(id: "a1b2c3d4", cpuUsageUsec: 1)
        ])
        let model = ContainerStatsModel(backend: backend)
        model.startStreaming(ids: ["a1b2c3d4"], interval: .milliseconds(10))
        try? await Task.sleep(for: .milliseconds(60))
        model.stop()
        let callsAtStop = backend.statsCallCount
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(
            backend.statsCallCount, callsAtStop, "polling must stop after stop() — no leaked task")
        XCTAssertFalse(model.isStreaming)
    }

    func testStopIsIdempotentAndClearsStreamingFlag() {
        let model = ContainerStatsModel(backend: MockBackend())
        model.startStreaming(ids: [])  // empty → no-op, not streaming
        XCTAssertFalse(model.isStreaming)
        model.stop()
        XCTAssertFalse(model.isStreaming)
    }
}
