//
//  SystemStatusModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import CapsuleDiagnostics
import XCTest

@testable import CapsuleDomain

@MainActor
final class SystemStatusModelTests: XCTestCase {
    func testRefreshOnRunningServiceBecomesRunningWithFeatures() async {
        let model = SystemStatusModel(backend: MockBackend())

        await model.refreshStatus()

        XCTAssertTrue(model.health.isRunning)
        XCTAssertTrue(model.health.availableFeatures.contains(.containers))
    }

    func testRefreshOnStoppedServiceBecomesStopped() async {
        let model = SystemStatusModel(backend: MockBackend(systemRunState: .stopped))

        await model.refreshStatus()

        XCTAssertEqual(model.health, .stopped)
    }

    func testRefreshOnUnreachableServiceBecomesUnavailable() async {
        let backend = MockBackend()
        backend.failure = BackendError.nonZeroExit(
            command: "container system status", code: 1, stderr: "Connection refused")
        let model = SystemStatusModel(backend: backend, normalize: ErrorNormalizer.normalize)

        await model.refreshStatus()

        guard case .unavailable = model.health else {
            return XCTFail("expected .unavailable, got \(model.health)")
        }
    }

    func testMissingExecutableProbesToNotInstalled() async {
        let backend = MockBackend()
        backend.failure = .executableNotFound("/usr/local/bin/container")
        let model = SystemStatusModel(
            backend: backend, normalize: { ErrorNormalizer.normalize($0) })
        await model.refreshStatus()
        guard case let .notInstalled(detail) = model.health else {
            return XCTFail("expected .notInstalled, got \(model.health)")
        }
        XCTAssertTrue(detail.recoveryActions.contains(.installContainerCLI))
    }

    func testStartServicesFlipsStoppedToRunning() async {
        let backend = MockBackend(systemRunState: .stopped)
        let model = SystemStatusModel(backend: backend)
        await model.refreshStatus()
        XCTAssertEqual(model.health, .stopped)

        await model.startServices()

        XCTAssertTrue(model.health.isRunning)
    }

    func testStartServicesRegistersActivityTask() async {
        let center = TaskCenter()
        let model = SystemStatusModel(
            backend: MockBackend(systemRunState: .stopped), taskCenter: center)
        await model.startServices()
        XCTAssertEqual(center.tasks.count, 1)
        XCTAssertEqual(center.tasks.first?.kind, .systemStart)
        XCTAssertTrue(model.health.isRunning)
    }

    func testStopServicesFlipsRunningToStopped() async {
        let model = SystemStatusModel(backend: MockBackend())
        await model.refreshStatus()
        XCTAssertTrue(model.health.isRunning)

        await model.stopServices()

        XCTAssertEqual(model.health, .stopped)
    }

    func testCompatibilityWarningSetForOldClient() async {
        let backend = MockBackend(version: BackendVersion(client: "0.9.0", server: "0.9.0"))
        // A 0.9.0 client derives no runtime features, so the service reads as running but
        // limited; the warning must still surface.
        let model = SystemStatusModel(backend: backend)

        await model.refreshStatus()

        XCTAssertNotNil(model.compatibilityWarning)
    }
}
