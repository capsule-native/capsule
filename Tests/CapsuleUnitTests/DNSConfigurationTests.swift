//
//  DNSConfigurationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  DNSConfiguration is the argv source for the privileged sudo Terminal handoff
//  (system dns create/delete). It is never run through the CLI adapter.

import CapsuleBackend
import XCTest

final class DNSConfigurationTests: XCTestCase {
    func testCreateArgvMinimal() {
        XCTAssertEqual(
            DNSConfiguration(domain: "capsule.test").arguments,
            ["system", "dns", "create", "capsule.test"])
    }

    func testCreateArgvWithLocalhost() {
        XCTAssertEqual(
            DNSConfiguration(domain: "capsule.test", localhostIP: "127.0.0.1").arguments,
            ["system", "dns", "create", "--localhost", "127.0.0.1", "capsule.test"])
    }

    func testDeleteArgv() {
        XCTAssertEqual(
            DNSConfiguration(domain: "capsule.test").deleteArguments,
            ["system", "dns", "delete", "capsule.test"])
    }
}
