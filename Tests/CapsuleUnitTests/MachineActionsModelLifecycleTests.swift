//
//  MachineActionsModelLifecycleTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleBackend
@testable import CapsuleDomain

@MainActor
final class MachineActionsModelLifecycleTests: XCTestCase {
    func test_stop_setsBanner_clearsRestart() async {
        let mock = MockBackend(machines: [MachineSummary(name: "dev", state: "running")])
        let a = MachineActionsModel(backend: mock, reloadList: {})
        a.pendingRestart.insert("dev")
        await a.stop("dev")
        XCTAssertEqual(mock.lastStoppedMachine, "dev")
        XCTAssertFalse(a.restartRequired("dev"))
        if case .stopped = a.banner?.kind {} else { XCTFail("banner") }
    }
    func test_delete_removes() async {
        let mock = MockBackend(machines: [MachineSummary(name: "dev")])
        let a = MachineActionsModel(backend: mock, reloadList: {})
        await a.delete("dev")
        XCTAssertEqual(mock.lastDeletedMachine, "dev")
    }
}
