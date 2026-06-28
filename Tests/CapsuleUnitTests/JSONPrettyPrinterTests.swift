//
//  JSONPrettyPrinterTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class JSONPrettyPrinterTests: XCTestCase {
    func testPrettyPrintsCompactJSON() {
        let out = JSONPrettyPrinter.prettyPrint(#"{"b":1,"a":2}"#)
        XCTAssertTrue(out.contains("\n"))
        // Sorted keys: "a" appears before "b".
        let a = out.range(of: "\"a\"")
        let b = out.range(of: "\"b\"")
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertTrue(a!.lowerBound < b!.lowerBound)
    }

    func testReturnsRawWhenNotJSON() {
        XCTAssertEqual(JSONPrettyPrinter.prettyPrint("not json"), "not json")
    }
}
