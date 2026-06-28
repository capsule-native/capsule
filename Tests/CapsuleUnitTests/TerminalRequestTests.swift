//
//  TerminalRequestTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class TerminalRequestTests: XCTestCase {
    func testStoresFieldsAndIsEquatableByContent() {
        let a = TerminalRequest(
            containerID: "c1", title: "Shell · c1",
            argv: ["container", "exec", "-it", "c1", "sh"], kind: .execShell)
        let b = TerminalRequest(
            containerID: "c1", title: "Shell · c1",
            argv: ["container", "exec", "-it", "c1", "sh"], kind: .execShell)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.argv, ["container", "exec", "-it", "c1", "sh"])
        XCTAssertEqual(a.kind, .execShell)
        XCTAssertEqual(a.containerID, "c1")
    }
}
