//
//  MachineActionsModelDefaultTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest
@testable import CapsuleBackend
@testable import CapsuleDomain

@MainActor
final class MachineActionsModelDefaultTests: XCTestCase {
    func test_makeDefault_thenRevert() async {
        let mock = MockBackend(machines: [
            MachineSummary(name: "a", isDefault: true),
            MachineSummary(name: "b"),
        ])
        let a = MachineActionsModel(backend: mock, reloadList: {})
        await a.makeDefault("b", previousDefault: "a")
        XCTAssertEqual(mock.lastSetDefaultID, "b")
        if case .madeDefault = a.banner?.kind {} else { XCTFail("banner") }
        await a.revertDefault()
        XCTAssertEqual(mock.lastSetDefaultID, "a")
    }
}
