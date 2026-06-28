//
//  BannerPresentationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import XCTest

@testable import CapsuleUI

final class BannerPresentationTests: XCTestCase {
    func testRunningShowsHealthyWithVersion() {
        let health = SystemHealth.running(
            version: SystemVersion(client: "1.0.0", server: "1.0.0"), features: [.containers])
        let text = SystemHealthBanner.bannerText(for: health, warning: nil)

        XCTAssertEqual(text.kind, .healthy)
        XCTAssertTrue(text.message.contains("1.0.0"))
    }

    func testStoppedShowsUnhealthy() {
        let text = SystemHealthBanner.bannerText(for: .stopped, warning: nil)

        XCTAssertEqual(text.kind, .unhealthy)
        XCTAssertTrue(text.title.lowercased().contains("stopped"))
    }

    func testUnavailableUsesErrorDetail() {
        let detail = ErrorDetail(
            title: "Container service unavailable", explanation: "It crashed.",
            recoveryActions: [.startServices])
        let text = SystemHealthBanner.bannerText(for: .unavailable(detail), warning: nil)

        XCTAssertEqual(text.kind, .unhealthy)
        XCTAssertEqual(text.title, "Container service unavailable")
        XCTAssertEqual(text.message, "It crashed.")
    }

    func testWarningDowngradesRunningToCaution() {
        let health = SystemHealth.running(
            version: SystemVersion(client: "1.2.0", server: "2.0.0"), features: [.containers])
        let text = SystemHealthBanner.bannerText(
            for: health, warning: "CLI and service major versions differ.")

        XCTAssertEqual(text.kind, .caution)
        XCTAssertTrue(text.message.contains("differ"))
    }

    func testStoppedRecoveryOffersStartServices() {
        XCTAssertTrue(SystemHealthBanner.recoveryActions(for: .stopped).contains(.startServices))
    }

    func testUnavailableRecoveryUsesDetailActions() {
        let detail = ErrorDetail(
            title: "x", explanation: "y", recoveryActions: [.openLogs, .exportDiagnostics])
        XCTAssertEqual(
            SystemHealthBanner.recoveryActions(for: .unavailable(detail)),
            [.openLogs, .exportDiagnostics])
    }
}
