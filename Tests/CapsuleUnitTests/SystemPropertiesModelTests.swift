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

    func testEditingFlagsRequiresRestartAndReview() async {
        let m = SystemPropertiesModel(
            backend: MockBackend(), normalize: { _ in .unknown(message: "test") })
        await m.load()
        XCTAssertFalse(m.requiresRestart)
        m.editBuffer = m.editBuffer.replacingOccurrences(of: "cpus = 2", with: "cpus = 8")
        // The spec requires the restart banner to appear ON EDIT: a dirty buffer drives
        // requiresRestart (the banner state), while the exported flag stays false until export.
        XCTAssertTrue(m.requiresRestart, "a dirty buffer must surface the restart banner")
        XCTAssertFalse(m.restartRequired, "editing alone does not mark the config exported")
        XCTAssertTrue(m.changeReview.contains { $0.contains("cpus") })
    }

    func testRevertClearsRequiresRestartWhenNeverExported() async {
        let m = SystemPropertiesModel(
            backend: MockBackend(), normalize: { _ in .unknown(message: "test") })
        await m.load()
        m.editBuffer = m.editBuffer.replacingOccurrences(of: "cpus = 2", with: "cpus = 8")
        XCTAssertTrue(m.requiresRestart)
        m.resetEdits()
        // No export happened, so reverting the buffer clears the banner.
        XCTAssertFalse(m.requiresRestart)
    }

    func testExportFlagsRestartAndResetDoesNotClear() async {
        // resetEdits() reverts the buffer but does NOT clear restartRequired —
        // the file on disk still contains the exported config; a restart is still needed.
        let m = SystemPropertiesModel(
            backend: MockBackend(), normalize: { _ in .unknown(message: "test") })
        await m.load()
        XCTAssertFalse(m.restartRequired)
        m.markExported()
        XCTAssertTrue(m.restartRequired)
        m.resetEdits()
        XCTAssertTrue(
            m.restartRequired,
            "resetEdits must not clear restartRequired — file on disk still differs from daemon state"
        )
    }

    func testLoadClearsRestartRequired() async {
        // load() establishes a new disk baseline; restartRequired is cleared.
        let m = SystemPropertiesModel(
            backend: MockBackend(), normalize: { _ in .unknown(message: "test") })
        await m.load()
        m.markExported()
        XCTAssertTrue(m.restartRequired)
        await m.load()
        XCTAssertFalse(m.restartRequired)
    }

    func testValidateSurfacesIssues() async {
        let m = SystemPropertiesModel(
            backend: MockBackend(), normalize: { _ in .unknown(message: "test") })
        await m.load()
        m.editBuffer = "cpus = 2\n"  // key outside section
        XCTAssertFalse(m.issues.isEmpty)
    }
}
