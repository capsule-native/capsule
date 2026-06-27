//
//  CLIBackendIntegrationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Integration tests exercise the real `container` CLI and therefore require an
//  Apple-silicon macOS host with the CLI installed. They self-skip unless
//  CAPSULE_INTEGRATION=1, so they stay green (skipped) in CI.

import CapsuleBackend
import XCTest

@testable import CapsuleCLIBackend

final class CLIBackendIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CAPSULE_INTEGRATION"] == "1",
            "Set CAPSULE_INTEGRATION=1 to run integration tests (requires the container CLI)."
        )
    }

    func testVersionReturnsClientString() async throws {
        let backend = CLIContainerBackend()
        let version = try await backend.version()
        XCTAssertFalse(version.client.isEmpty)
    }

    func testListContainersSucceeds() async throws {
        let backend = CLIContainerBackend()
        _ = try await backend.listContainers()
    }
}
