//
//  SystemSurfaceIntegrationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Gated integration test for the system surface reads against the real `container` CLI.
//  The test self-skips unless CAPSULE_INTEGRATION=1 is set, so CI stays green (skipped).
//  Read-only: no kernel install, no host mutation.

import CapsuleBackend
import XCTest

@testable import CapsuleCLIBackend

final class SystemSurfaceIntegrationTests: XCTestCase {

    // MARK: - Skip gate (mirrors CLIBackendIntegrationTests)

    private var integrationEnabled: Bool {
        ProcessInfo.processInfo.environment["CAPSULE_INTEGRATION"] == "1"
    }

    /// The single skip gate for every CLI-touching test.
    private func requireIntegration() throws {
        try XCTSkipUnless(
            integrationEnabled,
            "Set CAPSULE_INTEGRATION=1 to run integration tests (requires the container CLI)."
        )
    }

    // MARK: - Skip guard (always runs; never touches the CLI)

    func testGuardSkipsCleanlyWithoutEnv() throws {
        if integrationEnabled {
            XCTAssertEqual(ProcessInfo.processInfo.environment["CAPSULE_INTEGRATION"], "1")
        } else {
            // Flag unset => the CLI-touching tests skip rather than run or fail.
            XCTAssertNotEqual(ProcessInfo.processInfo.environment["CAPSULE_INTEGRATION"], "1")
        }
    }

    // MARK: - M10: system surface reads (df / versions / properties / logs)

    func testSystemReadsAgainstRealCLI() async throws {
        try requireIntegration()
        let backend = CLIContainerBackend()

        // 1. Disk usage — all totals must be non-negative.
        let usage = try await backend.systemDiskUsage()
        XCTAssertGreaterThanOrEqual(usage.images.sizeInBytes, 0)
        XCTAssertGreaterThanOrEqual(usage.containers.sizeInBytes, 0)
        XCTAssertGreaterThanOrEqual(usage.volumes.sizeInBytes, 0)

        // 2. Component versions — must include an entry for the `container` CLI itself.
        let comps = try await backend.systemComponentVersions()
        XCTAssertTrue(
            comps.contains { $0.appName == "container" },
            "systemComponentVersions should include a 'container' entry; got: \(comps.map(\.appName))"
        )

        // 3. Properties (structured) — must have at least a `build` or `kernel` section.
        let props = try await backend.systemProperties()
        XCTAssertTrue(
            props.sections.contains { $0.name == "kernel" || $0.name == "build" },
            "systemProperties should have a 'kernel' or 'build' section; got: \(props.sections.map(\.name))"
        )

        // 4. Properties (TOML) — must be non-empty.
        let toml = try await backend.systemPropertiesTOML()
        XCTAssertFalse(toml.isEmpty, "systemPropertiesTOML should return non-empty text")

        // 5. System logs — empty is valid; the call must NOT throw.
        _ = try await backend.fetchSystemLogs(last: "5m")
    }
}
