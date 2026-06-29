//
//  MachineBrowserModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
import XCTest

@testable import CapsuleBackend
@testable import CapsuleDomain

@MainActor
final class MachineBrowserModelTests: XCTestCase {
    func test_refresh_loaded_sortsAndStampsDefault() async {
        let mock = MockBackend(machines: MockBackend.sampleMachines)
        let m = MachineBrowserModel(backend: mock)
        await m.refresh()
        XCTAssertEqual(m.loadState, .loaded)
        XCTAssertEqual(m.rows.map(\.name), ["builder", "default"])  // name-sorted
        XCTAssertEqual(m.defaultMachine?.name, "default")
    }
    func test_refresh_empty_isHealthyEmpty() async {
        let m = MachineBrowserModel(backend: MockBackend(machines: []))
        await m.refresh()
        XCTAssertTrue(m.isEmptyButHealthy)
    }
    func test_refresh_failure_unavailable() async {
        let mock = MockBackend(machines: [])
        mock.failure = .nonZeroExit(command: "machine list", code: 1, stderr: "boom")
        let m = MachineBrowserModel(backend: mock)
        await m.refresh()
        if case .unavailable = m.loadState {} else { XCTFail("expected unavailable") }
    }
    func test_inspect_returnsRaw() async {
        let mock = MockBackend(machines: [MachineSummary(name: "dev")])
        let m = MachineBrowserModel(backend: mock)
        let insp = await m.inspect(id: "dev")
        XCTAssertEqual(insp.value?.name, "dev")
    }
}
