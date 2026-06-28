//
//  SecretRedactorTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDiagnostics

final class SecretRedactorTests: XCTestCase {
    private let mask = SecretRedactor.placeholder

    // MARK: - Argument arrays

    func testRedactsValueAfterPasswordFlag() {
        let argv = ["container", "registry", "login", "--password", "hunter2", "ghcr.io"]
        let redacted = SecretRedactor.redact(arguments: argv)
        XCTAssertEqual(
            redacted,
            ["container", "registry", "login", "--password", mask, "ghcr.io"]
        )
    }

    func testRedactsValueAfterShortPasswordFlag() {
        XCTAssertEqual(
            SecretRedactor.redact(arguments: ["login", "-p", "s3cret"]),
            ["login", "-p", mask]
        )
    }

    func testRedactsTokenAndSecretFlags() {
        XCTAssertEqual(
            SecretRedactor.redact(arguments: ["--token", "abc", "--secret", "xyz"]),
            ["--token", mask, "--secret", mask]
        )
    }

    func testRedactsInlineEqualsForm() {
        XCTAssertEqual(
            SecretRedactor.redact(arguments: ["--password=hunter2", "next"]),
            ["--password=\(mask)", "next"]
        )
    }

    func testDoesNotRedactUsername() {
        let argv = ["registry", "login", "--username", "alice", "ghcr.io"]
        XCTAssertEqual(SecretRedactor.redact(arguments: argv), argv)
    }

    func testTrailingSecretFlagWithoutValueIsSafe() {
        // A dangling flag must not crash or drop elements.
        XCTAssertEqual(
            SecretRedactor.redact(arguments: ["login", "--password"]),
            ["login", "--password"]
        )
    }

    // MARK: - Free text

    func testRedactsBearerToken() {
        let line = "Authorization: Bearer eyJhbGciOi.payload.sig"
        let redacted = SecretRedactor.redact(line)
        XCTAssertFalse(redacted.contains("eyJhbGciOi.payload.sig"))
        XCTAssertTrue(redacted.contains(mask))
    }

    func testRedactsPasswordFlagInsideText() {
        let line = "running: container registry login --password hunter2 ghcr.io"
        let redacted = SecretRedactor.redact(line)
        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertTrue(redacted.contains(mask))
    }

    func testLeavesOrdinaryTextUntouched() {
        let line = "Error: no such container: web"
        XCTAssertEqual(SecretRedactor.redact(line), line)
    }
}
