//
//  ConfirmationMachineTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest
@testable import CapsuleDomain

final class ConfirmationMachineTests: XCTestCase {
    func test_deleteMachine_warnsPersistentStorage() {
        let r = ConfirmationRequest.deleteMachine(name: "dev")
        XCTAssertEqual(r.kind, .deleteMachine)
        XCTAssertEqual(r.targetIDs, ["dev"])
        XCTAssertTrue(r.message.lowercased().contains("persistent"))
        XCTAssertEqual(r.confirmTitle, "Delete")
    }
}
