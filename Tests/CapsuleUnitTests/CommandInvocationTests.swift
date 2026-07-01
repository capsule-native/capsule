//
//  CommandInvocationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class CommandInvocationTests: XCTestCase {
    func testDefaultExecutableIsContainer() {
        let inv = CommandInvocation(["image", "list", "--format", "json"])
        XCTAssertEqual(inv.executable, "container")
        XCTAssertEqual(inv.arguments, ["image", "list", "--format", "json"])
    }

    func testArgvPrependsExecutable() {
        XCTAssertEqual(CommandInvocation(["system", "df"]).argv, ["container", "system", "df"])
    }

    func testRawDisplayIsUnredactedSpaceJoined() {
        let inv = CommandInvocation(["registry", "login", "--password", "hunter2"])
        XCTAssertEqual(inv.rawDisplay, "container registry login --password hunter2")
    }

    func testDisplayStringIsRedacted() {
        let inv = CommandInvocation(["registry", "login", "--password", "hunter2", "ghcr.io"])
        XCTAssertEqual(
            inv.displayString, "container registry login --password ‹redacted› ghcr.io")
    }

    func testDisplayStringNeverRedactsPublishPorts() {
        let inv = CommandInvocation(["run", "-p", "8080:80", "alpine"])
        XCTAssertEqual(inv.displayString, "container run -p 8080:80 alpine")
    }

    func testCustomExecutableIsHonoured() {
        let inv = CommandInvocation(["--help"], executable: "container-foo")
        XCTAssertEqual(inv.argv, ["container-foo", "--help"])
        XCTAssertEqual(inv.displayString, "container-foo --help")
    }

    func testEquatable() {
        XCTAssertEqual(CommandInvocation(["a", "b"]), CommandInvocation(["a", "b"]))
        XCTAssertNotEqual(
            CommandInvocation(["a"]), CommandInvocation(["a"], executable: "other"))
    }
}
