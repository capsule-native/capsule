//
//  AboutModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class AboutModelTests: XCTestCase {
    func testLoadsComponentsAndBuildsReport() async {
        let backend = MockBackend()
        let model = AboutModel(
            backend: backend, normalize: { _ in .unknown(message: "test") },
            appVersion: "0.10.0", osVersion: "macOS 26.0")
        await model.refresh()
        XCTAssertEqual(model.components.count, 2)
        XCTAssertTrue(model.bugReportText.contains("container"))
        XCTAssertTrue(model.bugReportText.contains("0.10.0"))
    }
    func testCompatibilityWarningOnVersionSkew() async {
        let backend = MockBackend()
        backend.componentVersions = [
            ComponentVersion(
                appName: "container", version: "1.0.0", buildType: "release", commit: "a"),
            ComponentVersion(
                appName: "container-apiserver",
                version: "container-apiserver version 0.9.0 (build: release, commit: b)",
                buildType: "release", commit: "b"),
        ]
        let model = AboutModel(
            backend: backend, normalize: { _ in .unknown(message: "test") },
            appVersion: "0.10.0", osVersion: "macOS 26.0")
        await model.refresh()
        XCTAssertFalse(model.compatibilityWarnings.isEmpty)
    }
}
