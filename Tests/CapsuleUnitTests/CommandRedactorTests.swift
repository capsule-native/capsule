//
//  CommandRedactorTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class CommandRedactorTests: XCTestCase {
    func testMasksTokenAfterSecretFlag() {
        XCTAssertEqual(
            CommandRedactor.redactedArguments(
                ["registry", "login", "--password", "hunter2", "ghcr.io"]),
            ["registry", "login", "--password", "‹redacted›", "ghcr.io"]
        )
        XCTAssertEqual(
            CommandRedactor.redactedArguments(
                ["--token", "abc", "--secret", "xyz", "--passphrase", "p"]),
            ["--token", "‹redacted›", "--secret", "‹redacted›", "--passphrase", "‹redacted›"]
        )
    }

    func testMasksEqualsFormOfSecretFlags() {
        XCTAssertEqual(
            CommandRedactor.redactedArguments(["--password=hunter2", "--token=abc"]),
            ["--password=‹redacted›", "--token=‹redacted›"]
        )
    }

    func testMasksSensitiveEnvAndBuildArgValuesByKey() {
        XCTAssertEqual(
            CommandRedactor.redactedArguments(["run", "-e", "DB_PASSWORD=s3cr3t", "img"]),
            ["run", "-e", "DB_PASSWORD=‹redacted›", "img"]
        )
        XCTAssertEqual(
            CommandRedactor.redactedArguments(
                ["--env", "API_TOKEN=t", "--build-arg", "MY_SECRET=v"]),
            ["--env", "API_TOKEN=‹redacted›", "--build-arg", "MY_SECRET=‹redacted›"]
        )
    }

    func testKeepsNonSensitiveEnvValues() {
        XCTAssertEqual(
            CommandRedactor.redactedArguments(["run", "-e", "PATH=/usr/bin", "img"]),
            ["run", "-e", "PATH=/usr/bin", "img"]
        )
    }

    func testNeverMasksPublishPorts() {
        XCTAssertEqual(
            CommandRedactor.redactedArguments(
                ["run", "-p", "8080:80", "--publish", "443:443", "img"]),
            ["run", "-p", "8080:80", "--publish", "443:443", "img"]
        )
    }

    func testLeavesTrailingSecretFlagUntouched() {
        // A secret flag with no following token: nothing to mask, no out-of-bounds.
        XCTAssertEqual(
            CommandRedactor.redactedArguments(["--password"]),
            ["--password"]
        )
    }
}
