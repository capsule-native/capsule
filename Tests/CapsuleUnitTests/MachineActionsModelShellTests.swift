//
//  MachineActionsModelShellTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest
@testable import CapsuleBackend
@testable import CapsuleDomain

@MainActor
final class MachineActionsModelShellTests: XCTestCase {
    func test_shellArgv() {
        let a = MachineActionsModel(backend: MockBackend(machines: []), reloadList: {})
        let expected = ["container", "machine", "run", "-it", "-n", "dev"]
        XCTAssertEqual(a.shellArgv(name: "dev"), expected)
    }

    func test_shellArgv_emptyName_omitsNameFlag() {
        let a = MachineActionsModel(backend: MockBackend(machines: []), reloadList: {})
        XCTAssertEqual(a.shellArgv(name: ""), ["container", "machine", "run", "-it"])
    }

    func test_openShell_stopped_setsImplicitBootBanner_andLaunches() {
        var launched: [String]?
        let a = MachineActionsModel(
            backend: MockBackend(machines: []), reloadList: {},
            currentState: { _ in .stopped }, terminalAvailable: { true },
            launchTerminal: { launched = $0.argv })
        a.openShell(name: "dev")
        XCTAssertEqual(launched, ["container", "machine", "run", "-it", "-n", "dev"])
        if case .implicitBoot = a.banner?.kind {} else { XCTFail("implicit boot banner") }
    }

    func test_openShell_running_noImplicitBootBanner() {
        let a = MachineActionsModel(
            backend: MockBackend(machines: []), reloadList: {},
            currentState: { _ in .running }, terminalAvailable: { true }, launchTerminal: { _ in })
        a.openShell(name: "dev")
        XCTAssertNil(a.banner)
    }
}
