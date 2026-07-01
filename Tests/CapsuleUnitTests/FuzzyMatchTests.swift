//
//  FuzzyMatchTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class FuzzyMatchTests: XCTestCase {
    func testSubsequenceMatches() {
        XCTAssertTrue(FuzzyMatch.matches("rsi", "Run Selected Image"))
        XCTAssertTrue(FuzzyMatch.matches("", "anything"))
        XCTAssertFalse(FuzzyMatch.matches("zqx", "Run Selected Image"))
    }

    func testScoreNilWhenNoMatch() {
        XCTAssertNil(FuzzyMatch.score("xyz", "Pull Image"))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(FuzzyMatch.matches("PULL", "pull image"))
    }

    func testContiguousPrefixScoresBetterThanScattered() {
        let tight = FuzzyMatch.score("pul", "Pull Image")
        let loose = FuzzyMatch.score("pul", "Preview Ultra Long")
        XCTAssertNotNil(tight)
        XCTAssertNotNil(loose)
        if let tight, let loose { XCTAssertLessThan(tight, loose) }
    }
}
