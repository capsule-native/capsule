//
//  SystemPropertiesModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class SystemPropertiesModelTests: XCTestCase {
    func testLoadPopulatesSectionsAndBuffer() async {
        let m = SystemPropertiesModel(
            backend: MockBackend(), normalize: { _ in .unknown(message: "test") })
        await m.load()
        XCTAssertFalse(m.sections.isEmpty)
        XCTAssertTrue(m.editBuffer.contains("[build]"))
        XCTAssertFalse(m.restartRequired)
    }

    func testEditingFlagsRestartAndReview() async {
        let m = SystemPropertiesModel(
            backend: MockBackend(), normalize: { _ in .unknown(message: "test") })
        await m.load()
        m.editBuffer = m.editBuffer.replacingOccurrences(of: "cpus = 2", with: "cpus = 8")
        m.markEdited()
        // Editing alone must NOT flag restart — only markExported() does that.
        XCTAssertFalse(m.restartRequired)
        XCTAssertTrue(m.changeReview.contains { $0.contains("cpus") })
    }

    func testExportFlagsRestartAndResetClears() async {
        let m = SystemPropertiesModel(
            backend: MockBackend(), normalize: { _ in .unknown(message: "test") })
        await m.load()
        XCTAssertFalse(m.restartRequired)
        m.markExported()
        XCTAssertTrue(m.restartRequired)
        m.resetEdits()
        XCTAssertFalse(m.restartRequired)
    }

    func testValidateSurfacesIssues() async {
        let m = SystemPropertiesModel(
            backend: MockBackend(), normalize: { _ in .unknown(message: "test") })
        await m.load()
        m.editBuffer = "cpus = 2\n"  // key outside section
        m.markEdited()
        XCTAssertFalse(m.issues.isEmpty)
    }
}
