//
//  DNSDomainTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

final class DNSDomainTests: XCTestCase {
    func testInitFromSummaryMapsFields() {
        let summary = DNSDomainSummary(domain: "test", localhostIP: "127.0.0.1")
        let domain = DNSDomain(summary: summary)
        XCTAssertEqual(domain.domain, "test")
        XCTAssertEqual(domain.localhostIP, "127.0.0.1")
        XCTAssertEqual(domain.id, "test")
    }

    func testInitFromSummaryWithoutIP() {
        let domain = DNSDomain(summary: DNSDomainSummary(domain: "app.test"))
        XCTAssertEqual(domain.domain, "app.test")
        XCTAssertNil(domain.localhostIP)
    }

    func testDraftDefaultsAreEmpty() {
        let draft = DNSDraft()
        XCTAssertTrue(draft.domain.isEmpty)
        XCTAssertTrue(draft.localhostIP.isEmpty)
    }
}
