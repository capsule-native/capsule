//
//  MachineSummaryTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
import XCTest
@testable import CapsuleBackend

final class MachineSummaryTests: XCTestCase {
    func test_init_defaults_onlyNameRequired() {
        let m = MachineSummary(name: "dev")
        XCTAssertEqual(m.id, "dev")
        XCTAssertNil(m.state)
        XCTAssertFalse(m.isDefault)
        XCTAssertNil(m.cpus)
    }

    func test_carriesListColumns() {
        let m = MachineSummary(
            name: "dev", state: "running", createdAt: "2026-06-29T00:00:00Z",
            ipAddress: "192.168.66.2", cpus: 4, memory: "8G", disk: "20G", isDefault: true)
        XCTAssertEqual(m.cpus, 4)
        XCTAssertEqual(m.memory, "8G")
        XCTAssertTrue(m.isDefault)
        XCTAssertEqual(m.ipAddress, "192.168.66.2")
    }
}
