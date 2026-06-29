//
//  VolumeDraftTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class VolumeDraftTests: XCTestCase {
    func testKeyValueRowTokenOmitsEmptyKey() {
        XCTAssertNil(KeyValueRow(key: "", value: "anything").token)
        XCTAssertEqual(KeyValueRow(key: "journaling", value: "on").token, "journaling=on")
        XCTAssertEqual(KeyValueRow(key: "flag", value: "").token, "flag=")
    }

    func testKeyValueRowsAreUniquelyIdentified() {
        XCTAssertNotEqual(KeyValueRow().id, KeyValueRow().id)
    }

    func testVolumeDraftDefaultsAreEmpty() {
        let draft = VolumeDraft()
        XCTAssertTrue(draft.name.isEmpty)
        XCTAssertTrue(draft.size.isEmpty)
        XCTAssertTrue(draft.options.isEmpty)
        XCTAssertTrue(draft.labels.isEmpty)
    }

    func testIsValidSizeAcceptsSuffixedNumbers() {
        XCTAssertTrue(VolumeDraft.isValidSize("10G"))
        XCTAssertTrue(VolumeDraft.isValidSize("512m"))
        XCTAssertTrue(VolumeDraft.isValidSize("1.5T"))
        XCTAssertTrue(VolumeDraft.isValidSize("100K"))
        XCTAssertTrue(VolumeDraft.isValidSize("2P"))
    }

    func testIsValidSizeRejectsMissingOrBadSuffix() {
        XCTAssertFalse(VolumeDraft.isValidSize("10"))
        XCTAssertFalse(VolumeDraft.isValidSize("G"))
        XCTAssertFalse(VolumeDraft.isValidSize("ten G"))
        XCTAssertFalse(VolumeDraft.isValidSize("10GB"))
    }
}
