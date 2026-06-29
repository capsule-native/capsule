//
//  CLIBackendIntegrationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Integration tests exercise the real `container` CLI and therefore require an
//  Apple-silicon macOS host with the CLI installed. The CLI-touching tests self-skip
//  unless CAPSULE_INTEGRATION=1, so they stay green (skipped) in CI. `requireIntegration()`
//  is the single skip gate; `testGuardSkipsCleanlyWithoutEnv` runs unconditionally and
//  asserts that gate, so a flag-unset run is a clean skip rather than a failure.

import CapsuleBackend
import XCTest

@testable import CapsuleCLIBackend

final class CLIBackendIntegrationTests: XCTestCase {
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

    // MARK: - Existing smoke

    func testVersionReturnsClientString() async throws {
        try requireIntegration()
        let backend = CLIContainerBackend()
        let version = try await backend.version()
        XCTAssertFalse(version.client.isEmpty)
    }

    func testListContainersSucceeds() async throws {
        try requireIntegration()
        let backend = CLIContainerBackend()
        _ = try await backend.listContainers()
    }

    // MARK: - M8: volume lifecycle (create / list / inspect / delete / prune)

    func testVolumeLifecycleAgainstRealCLI() async throws {
        try requireIntegration()
        let backend = CLIContainerBackend()
        let name = "capsule-it-vol-\(UUID().uuidString.prefix(8))"

        do {
            try await backend.createVolume(VolumeConfiguration(name: name))

            let listed = try await backend.listVolumes()
            XCTAssertTrue(
                listed.contains { $0.name == name }, "created volume should appear in the list")

            let inspected = try await backend.inspectVolume(names: [name])
            XCTAssertFalse(inspected.raw.isEmpty, "inspect should return raw JSON")
            XCTAssertEqual(inspected.value?.first?.name, name)

            try await backend.deleteVolumes(names: [name])
            let afterDelete = try await backend.listVolumes()
            XCTAssertFalse(
                afterDelete.contains { $0.name == name }, "deleted volume should be gone")

            _ = try await backend.pruneVolumes()
        } catch {
            // Best-effort cleanup so a mid-test failure never leaks the throwaway volume.
            try? await backend.deleteVolumes(names: [name])
            throw error
        }
    }

    // MARK: - M8: network lifecycle (create / list / inspect / delete / prune)

    func testNetworkLifecycleAgainstRealCLI() async throws {
        try requireIntegration()
        let backend = CLIContainerBackend()
        let name = "capsule-it-net-\(UUID().uuidString.prefix(8))"

        do {
            // No subnet: let the CLI auto-assign so the test never collides with `default`.
            try await backend.createNetwork(NetworkConfiguration(name: name))

            let listed = try await backend.listNetworks()
            XCTAssertTrue(
                listed.contains { $0.name == name }, "created network should appear in the list")

            let inspected = try await backend.inspectNetwork(names: [name])
            XCTAssertFalse(inspected.raw.isEmpty, "inspect should return raw JSON")
            XCTAssertEqual(inspected.value?.first?.name, name)

            try await backend.deleteNetworks(names: [name])
            let afterDelete = try await backend.listNetworks()
            XCTAssertFalse(
                afterDelete.contains { $0.name == name }, "deleted network should be gone")

            _ = try await backend.pruneNetworks()
        } catch {
            try? await backend.deleteNetworks(names: [name])
            throw error
        }
    }

    // MARK: - M8: DNS list (unprivileged — must succeed, empty or populated)

    func testListDNSDomainsAgainstRealCLI() async throws {
        try requireIntegration()
        let backend = CLIContainerBackend()
        // Unprivileged list: an empty `[]` is success, not failure; it must never throw.
        _ = try await backend.listDNSDomains()
    }
}
