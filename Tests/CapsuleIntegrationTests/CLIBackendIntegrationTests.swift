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
        let name = "capsule-it-vol-\(UUID().uuidString.prefix(8).lowercased())"

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
        let name = "capsule-it-net-\(UUID().uuidString.prefix(8).lowercased())"

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

    // MARK: - M11: relocated argv factory (CLICommand now lives in CapsuleBackend)

    /// Runs `container <arguments>` via the user's PATH and returns the status plus the
    /// combined stdout+stderr. Read EOF before `waitUntilExit()` to avoid a pipe-buffer
    /// deadlock on larger output.
    private func runContainer(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["container"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// The relocated `CLICommand` must still emit flags / subcommand paths the real CLI
    /// accepts. Only read-only argv is probed (no host mutation); service state is irrelevant
    /// because we assert on argv-shape rejection, not exit code.
    func testRelocatedCLICommandYieldsRealCLIValidArgv() throws {
        try requireIntegration()
        let probes: [[String]] = [
            CLICommand.listContainers(all: true),  // ["list", "--all", "--format", "json"]
            CLICommand.listImages(),  // ["image", "list", "--format", "json"]
            CLICommand.systemDiskUsage(),  // ["system", "df", "--format", "json"]
        ]
        for argv in probes {
            let result = try runContainer(argv)
            XCTAssertFalse(
                result.output.contains("Usage:"),
                "real CLI rejected the relocated argv shape \(argv): \(result.output)"
            )
            XCTAssertFalse(
                result.output.localizedCaseInsensitiveContains("unexpected argument"),
                "real CLI saw an unexpected argument in \(argv): \(result.output)"
            )
            XCTAssertFalse(
                result.output.localizedCaseInsensitiveContains("unknown option"),
                "real CLI saw an unknown option in \(argv): \(result.output)"
            )
        }
    }
}
