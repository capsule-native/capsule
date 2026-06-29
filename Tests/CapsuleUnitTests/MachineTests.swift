//
//  MachineTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleBackend
@testable import CapsuleDomain

final class MachineTests: XCTestCase {
    func test_fromSummary_mapsFields() {
        let s = MachineSummary(
            name: "dev", state: "running", createdAt: "2026-06-20T09:15:00Z",
            ipAddress: "192.168.66.2", cpus: 4, memory: "8G", disk: "20G", isDefault: true,
            homeMount: "rw")
        let m = Machine(summary: s)
        XCTAssertEqual(m.id, "dev")
        XCTAssertEqual(m.state, .running)
        XCTAssertTrue(m.isDefault)
        XCTAssertEqual(m.cpus, 4)
        XCTAssertNotNil(m.createdAt)
    }
}
