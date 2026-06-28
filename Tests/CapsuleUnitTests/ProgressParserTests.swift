//
//  ProgressParserTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class ProgressParserTests: XCTestCase {
    func testParsesCleanPercent() throws {
        try XCTAssertEqual(
            XCTUnwrap(ProgressParser.fraction(in: "Downloading 42%")), 0.42, accuracy: 0.001)
        try XCTAssertEqual(
            XCTUnwrap(ProgressParser.fraction(in: "[100%] done")), 1.0, accuracy: 0.001)
        try XCTAssertEqual(
            XCTUnwrap(ProgressParser.fraction(in: "0% complete")), 0.0, accuracy: 0.001)
    }

    func testIgnoresLinesWithoutPercent() {
        XCTAssertNil(ProgressParser.fraction(in: "Step 2/5 : RUN echo hi"))
        XCTAssertNil(ProgressParser.fraction(in: "pulling layer sha256:abc"))
        XCTAssertNil(ProgressParser.fraction(in: "100 percent but no symbol"))
    }

    func testTakesLastPercentAndClamps() throws {
        try XCTAssertEqual(
            XCTUnwrap(ProgressParser.fraction(in: "a 10% b 80%")), 0.80, accuracy: 0.001)
        try XCTAssertEqual(XCTUnwrap(ProgressParser.fraction(in: "999%")), 1.0, accuracy: 0.001)
    }

    func testLoneSymbolIsNotProgress() {
        XCTAssertNil(ProgressParser.fraction(in: "discount of % applied"))
    }
}
