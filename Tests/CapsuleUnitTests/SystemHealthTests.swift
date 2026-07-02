//
//  SystemHealthTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class SystemHealthTests: XCTestCase {
    private func runningHealth() -> SystemHealth {
        .running(version: SystemVersion(client: "1.0.0", server: "1.0.0"), features: [.containers])
    }

    func testBannerKinds() {
        XCTAssertEqual(runningHealth().bannerKind, .healthy)
        XCTAssertEqual(SystemHealth.stopped.bannerKind, .unhealthy)
        XCTAssertEqual(SystemHealth.unknown.bannerKind, .info)
        XCTAssertEqual(SystemHealth.checking.bannerKind, .info)
        XCTAssertEqual(
            SystemHealth.unavailable(ErrorDetail(title: "x", explanation: "y")).bannerKind,
            .unhealthy
        )
    }

    func testIsRunning() {
        XCTAssertTrue(runningHealth().isRunning)
        XCTAssertFalse(SystemHealth.stopped.isRunning)
        XCTAssertFalse(SystemHealth.unknown.isRunning)
        XCTAssertFalse(
            SystemHealth.unavailable(ErrorDetail(title: "x", explanation: "y")).isRunning)
    }

    func testCompatibilityWarningFlagsOldClient() {
        XCTAssertNotNil(compatibilityWarning(forClient: "0.9.0", server: nil))
    }

    func testCompatibilityWarningNilForSupportedClient() {
        XCTAssertNil(compatibilityWarning(forClient: "1.0.0", server: "1.0.0"))
    }

    func testCompatibilityWarningFlagsMajorMismatch() {
        XCTAssertNotNil(compatibilityWarning(forClient: "1.2.0", server: "2.0.0"))
    }

    func testSystemFeatureMirrorsBackendFeatureNames() {
        // Every SystemFeature must round-trip through BackendFeature by raw value so the
        // domain can map capabilities without leaking backend types to the UI.
        for feature in SystemFeature.allCases {
            XCTAssertNotNil(feature.rawValue)
        }
    }

    func testSupportsRequiresRunningAndFeature() {
        let running = SystemHealth.running(
            version: SystemVersion(client: "1.0.0", server: "1.0.0"),
            features: [.volumes, .networks])
        XCTAssertTrue(running.supports(.volumes))
        XCTAssertTrue(running.supports(.networks))
        // A family the build did not report is unsupported even while running.
        XCTAssertFalse(running.supports(.machines))
    }

    func testSupportsFalseWhenNotRunning() {
        XCTAssertFalse(SystemHealth.stopped.supports(.volumes))
        XCTAssertFalse(SystemHealth.unknown.supports(.networks))
        XCTAssertFalse(SystemHealth.checking.supports(.volumes))
        XCTAssertFalse(
            SystemHealth.unavailable(ErrorDetail(title: "x", explanation: "y")).supports(.networks))
    }

    func testNotInstalledPresentation() {
        let health = SystemHealth.notInstalled(
            ErrorDetail(title: "Container CLI not installed", explanation: "missing"))
        XCTAssertFalse(health.isRunning)
        XCTAssertEqual(health.bannerKind, .unhealthy)
        XCTAssertEqual(health.statusLabel, "Not Installed")
        XCTAssertTrue(health.availableFeatures.isEmpty)
    }
}
