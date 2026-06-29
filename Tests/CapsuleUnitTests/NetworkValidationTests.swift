//
//  NetworkValidationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The pure subnet-conflict check: empty is allowed (CLI auto-assigns), malformed yields a
//  syntax hint, and an overlap names the conflicting network and both subnets.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

final class NetworkValidationTests: XCTestCase {
    private func net(_ name: String, v4: String? = nil, v6: String? = nil) -> Network {
        Network(summary: NetworkSummary(id: name, name: name, subnet: v4, ipv6Subnet: v6))
    }

    func testEmptyOrBlankSubnetIsAllowed() {
        XCTAssertNil(NetworkValidation.subnetConflict(subnet: "", against: []))
        XCTAssertNil(NetworkValidation.subnetConflict(subnet: "   ", against: []))
    }

    func testMalformedSubnetYieldsSyntaxHint() {
        let message = NetworkValidation.subnetConflict(subnet: "not-a-cidr", against: [])
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("/") ?? false, "the hint shows an example CIDR")
    }

    func testOverlapNamesTheConflictingNetworkAndBothSubnets() {
        let existing = [net("default", v4: "192.168.64.0/24")]
        let message = NetworkValidation.subnetConflict(
            subnet: "192.168.64.128/25", against: existing)
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("default") ?? false)
        XCTAssertTrue(message?.contains("192.168.64.0/24") ?? false, "names the existing subnet")
        XCTAssertTrue(message?.contains("192.168.64.128/25") ?? false, "echoes the attempt")
    }

    func testNonOverlappingSubnetIsClear() {
        let existing = [net("default", v4: "192.168.64.0/24")]
        XCTAssertNil(NetworkValidation.subnetConflict(subnet: "10.0.0.0/24", against: existing))
    }

    func testIPv4SubnetDoesNotConflictWithIPv6Existing() {
        let existing = [net("v6net", v6: "fd00::/32")]
        XCTAssertNil(
            NetworkValidation.subnetConflict(subnet: "10.0.0.0/24", against: existing),
            "different families never overlap")
    }

    func testIPv6OverlapIsDetected() {
        let existing = [net("v6net", v6: "fd00::/32")]
        let message = NetworkValidation.subnetConflict(subnet: "fd00:0:0:1::/64", against: existing)
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("v6net") ?? false)
    }
}
