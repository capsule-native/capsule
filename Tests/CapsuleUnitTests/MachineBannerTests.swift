//
//  MachineBannerTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest
@testable import CapsuleDomain

final class MachineBannerTests: XCTestCase {
    func test_madeDefault_hasUndoableMessage() {
        let b = MachineBanner(kind: .madeDefault(name: "dev", previous: "old"))
        XCTAssertTrue(b.message.contains("dev"))
        XCTAssertFalse(b.id.isEmpty)
    }
    func test_implicitBoot_mentionsBooting() {
        let b = MachineBanner(kind: .implicitBoot(name: "dev"))
        XCTAssertTrue(b.message.lowercased().contains("boot"))
    }
}
