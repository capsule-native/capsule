//
//  MachineDraftTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest
@testable import CapsuleDomain

final class MachineDraftTests: XCTestCase {
    func test_draftDefaults() {
        let d = MachineDraft()
        XCTAssertEqual(d.homeMount, "rw")
        XCTAssertFalse(d.setDefault)
    }
    func test_settingsDraft_seedsFromMachine() {
        let m = Machine(id: "dev", name: "dev", cpus: 4, memory: "8G", homeMount: "ro")
        let s = MachineSettingsDraft(machine: m)
        XCTAssertEqual(s.cpus, "4")
        XCTAssertEqual(s.memory, "8G")
        XCTAssertEqual(s.homeMount, "ro")
    }
}
