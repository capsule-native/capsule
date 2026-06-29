//
//  CIDRTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class CIDRTests: XCTestCase {
    // MARK: - parse

    func testParsesIPv4CIDR() throws {
        let parsed = try XCTUnwrap(CIDR.parse("192.168.64.0/24"))
        XCTAssertFalse(parsed.isIPv6)
        XCTAssertEqual(parsed.prefixLength, 24)
        XCTAssertEqual(parsed.bytes, [192, 168, 64, 0])
    }

    func testParsesIPv6CIDR() throws {
        let parsed = try XCTUnwrap(CIDR.parse("fdb6:5eb:8ee:85cf::/64"))
        XCTAssertTrue(parsed.isIPv6)
        XCTAssertEqual(parsed.prefixLength, 64)
        XCTAssertEqual(parsed.bytes.count, 16)
        XCTAssertEqual(Array(parsed.bytes.prefix(4)), [0xfd, 0xb6, 0x05, 0xeb])
    }

    func testParsesCompressedAndUnspecifiedIPv6() throws {
        XCTAssertEqual(try XCTUnwrap(CIDR.parse("::/0")).bytes, Array(repeating: 0, count: 16))
        let fd00 = try XCTUnwrap(CIDR.parse("fd00::/8"))
        XCTAssertEqual(Array(fd00.bytes.prefix(2)), [0xfd, 0x00])
    }

    func testParseRejectsMalformedInput() {
        XCTAssertNil(CIDR.parse("not-a-cidr"))
        XCTAssertNil(CIDR.parse("192.168.0.1"))  // no prefix
        XCTAssertNil(CIDR.parse("192.168.0.0/33"))  // IPv4 prefix too large
        XCTAssertNil(CIDR.parse("999.1.1.1/24"))  // octet out of range
        XCTAssertNil(CIDR.parse("10.0.0.0/"))  // empty prefix
        XCTAssertNil(CIDR.parse("10.0.0.0/x"))  // non-numeric prefix
        XCTAssertNil(CIDR.parse("::/200"))  // IPv6 prefix too large
        XCTAssertNil(CIDR.parse("fd00:::1/64"))  // double "::" twice
        XCTAssertNil(CIDR.parse(""))  // empty string
    }
}
