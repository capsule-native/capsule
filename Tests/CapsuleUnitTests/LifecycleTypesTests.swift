//
//  LifecycleTypesTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

final class LifecycleTypesTests: XCTestCase {
    func testMetricsMapFromSampleAndComputeMemoryPercent() {
        let sample = ContainerStatsSample(
            id: "c1", memoryUsageBytes: 50, memoryLimitBytes: 200, numProcesses: 2)
        let m = ContainerMetrics(
            sample: sample, capturedAt: Date(timeIntervalSince1970: 1), cpuPercent: 12.5)
        XCTAssertEqual(m.id, "c1")
        XCTAssertEqual(m.cpuPercent, 12.5)
        XCTAssertEqual(m.memoryPercent ?? -1, 25.0, accuracy: 0.001)
        XCTAssertEqual(m.numProcesses, 2)
    }

    func testMetricsMemoryPercentNilWhenLimitMissing() {
        let m = ContainerMetrics(
            sample: ContainerStatsSample(id: "c1", memoryUsageBytes: 50),
            capturedAt: Date(), cpuPercent: nil)
        XCTAssertNil(m.memoryPercent)
    }

    func testAttachSessionRingBufferCap() {
        var session = AttachSession()
        for i in 0..<250 { session.append(LogLine(id: i, stream: .standard, text: "\(i)")) }
        XCTAssertEqual(session.lines.count, 200)
        XCTAssertEqual(session.lines.first?.id, 50)  // oldest 50 trimmed
        XCTAssertTrue(session.isReadOnly)
    }

    func testLogLineMapsStderrSource() {
        XCTAssertEqual(LogLine(id: 1, source: .stderr, text: "x").stream, .error)
        XCTAssertEqual(LogLine(id: 2, source: .stdout, text: "y").stream, .standard)
    }

    func testStartResultOperationStatus() {
        XCTAssertEqual(ContainerStartResult.started(attached: false).operationStatus, .succeeded)
        XCTAssertEqual(
            ContainerStartResult.backendUnavailable.operationStatus, .backendUnavailable)
        XCTAssertEqual(
            ContainerStartResult.failedBeforeExecution.operationStatus, .failedBeforeExecution)
        XCTAssertEqual(ContainerStartResult.runFailed.operationStatus, .failedDuringExecution)
    }
}
