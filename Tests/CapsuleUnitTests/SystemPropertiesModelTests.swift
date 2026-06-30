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
        // Editing alone must NOT flag restart — only markExported() does that.
        XCTAssertFalse(m.restartRequired)
        XCTAssertTrue(m.changeReview.contains { $0.contains("cpus") })
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
