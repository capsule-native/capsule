//
//  NetworkDraftTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Create Network sheet's editable draft: raw UI strings + key/value rows that the
//  actions model validates into a NetworkConfiguration.

import XCTest

@testable import CapsuleDomain

final class NetworkDraftTests: XCTestCase {
    func testDefaultsAreEmptyAndNotInternal() {
        let draft = NetworkDraft()
        XCTAssertTrue(draft.name.isEmpty)
        XCTAssertTrue(draft.subnet.isEmpty)
        XCTAssertTrue(draft.subnetV6.isEmpty)
        XCTAssertFalse(draft.isInternal)
        XCTAssertTrue(draft.options.isEmpty)
        XCTAssertTrue(draft.labels.isEmpty)
        XCTAssertTrue(draft.plugin.isEmpty)
    }

    func testRowsCarryKeyValueTokens() {
        let draft = NetworkDraft(
            name: "app-net",
            options: [KeyValueRow(key: "mtu", value: "1400")],
            labels: [KeyValueRow(key: "team", value: "infra"), KeyValueRow()])
        XCTAssertEqual(draft.options.compactMap(\.token), ["mtu=1400"])
        XCTAssertEqual(draft.labels.compactMap(\.token), ["team=infra"], "blank rows drop out")
    }
}
