//
//  LogsModelSourceTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Verifies the LogSource seam: machine-source snapshot delivers lines, and the back-compat
//  container-source init (LogsModel(backend:)) still compiles and works unchanged.

import XCTest

@testable import CapsuleBackend
@testable import CapsuleDomain

@MainActor
final class LogsModelSourceTests: XCTestCase {
    func test_machineSource_snapshot() async {
        let mock = MockBackend(machines: [MachineSummary(name: "dev")])
        let model = LogsModel(source: .machine(mock))
        model.follow = false
        model.boot = true
        model.start(id: "dev")
        await model.waitForLoad()
        XCTAssertFalse(model.lines.isEmpty)
    }

    func test_containerSource_backCompat() async {
        let model = LogsModel(backend: MockBackend())  // existing init still works
        model.follow = false
        model.start(id: "a1b2c3d4")
        await model.waitForLoad()
        XCTAssertFalse(model.lines.isEmpty)
    }

    @MainActor
    func testSystemSourceFetchesViaLastWindow() async {
        // systemLogLines = ["apiserver: started", "apiserver: listening"]
        let backend = MockBackend()
        let model = LogsModel(source: .system(backend))
        model.follow = false
        model.lastMinutes = 60
        model.start(id: "")
        await model.waitForLoad()
        XCTAssertEqual(model.lines.map(\.text), ["apiserver: started", "apiserver: listening"])
        // Verify the window-to-minutes mapping: 60 → "60m", not "60s" or any other unit.
        XCTAssertEqual(backend.capturedLast, "60m")
    }

    @MainActor
    func testSystemSourceUsesDefaultWindow_whenLastMinutesIsNil() async {
        let backend = MockBackend()
        let model = LogsModel(source: .system(backend))
        model.follow = false
        // lastMinutes is nil — system source must fall back to the 5-minute default.
        model.start(id: "")
        await model.waitForLoad()
        XCTAssertEqual(backend.capturedLast, "5m")
    }
}
