//
//  MachineIntegrationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Gated integration test for the machine lifecycle against the real `container` CLI.
//  The test self-skips unless CAPSULE_INTEGRATION=1 is set, so CI stays green (skipped).

import CapsuleBackend
import XCTest

@testable import CapsuleCLIBackend

final class MachineIntegrationTests: XCTestCase {

    // MARK: - Skip gate (mirrors CLIBackendIntegrationTests)

    private var integrationEnabled: Bool {
        ProcessInfo.processInfo.environment["CAPSULE_INTEGRATION"] == "1"
    }

    private func requireIntegration() throws {
        try XCTSkipUnless(
            integrationEnabled,
            "Set CAPSULE_INTEGRATION=1 to run integration tests (requires the container CLI)."
        )
    }

    // MARK: - M9: machine lifecycle (create / list / inspect / set / set-default / logs / stop / delete)

    /// Fixed machine name — constant suffix so cleanup is reliable and traces are readable.
    private let machineName = "capsule-it-m9"

    func testMachineLifecycleAgainstRealCLI() async throws {
        try requireIntegration()
        let backend = CLIContainerBackend()

        do {
            // 1. Create — drain the progress stream (create pulls + boots the image).
            for try await _ in backend.createMachine(
                MachineConfiguration(image: "alpine:3.22", name: machineName, cpus: 2, memory: "2G")
            ) {}

            // 2. List — machine must appear.
            let listed = try await backend.listMachines()
            XCTAssertTrue(
                listed.contains { $0.name == machineName },
                "created machine '\(machineName)' should appear in the list")

            // 3. Inspect — raw JSON must be non-empty; decoded value must carry the name.
            let inspected = try await backend.inspectMachine(id: machineName)
            XCTAssertFalse(inspected.raw.isEmpty, "inspect should return raw JSON")
            XCTAssertEqual(inspected.value?.name, machineName, "inspected name should match")
            XCTAssertNotNil(inspected.value?.state, "inspected state should be present")

            // 4. Set — cpus change is accepted (takes effect after restart; assert no throw only).
            try await backend.setMachine(name: machineName, settings: MachineSettings(cpus: 1))

            // 5. Set-default — marks this machine as the default; assert no throw.
            try await backend.setDefaultMachine(id: machineName)

            // 6. Logs — may be empty for a freshly booted alpine machine; must not throw.
            _ = try await backend.fetchMachineLogs(id: machineName, tail: 20, boot: true)

            // 7. Stop — must not throw.
            try await backend.stopMachine(id: machineName)

            // 8. Delete — must not throw.
            try await backend.deleteMachine(id: machineName)

            // 9. List again — machine must be absent.
            let afterDelete = try await backend.listMachines()
            XCTAssertFalse(
                afterDelete.contains { $0.name == machineName },
                "deleted machine '\(machineName)' should be absent from the list")

        } catch {
            // Best-effort teardown: stop first (ignoring errors), then delete, so a mid-test
            // failure never leaves a running or lingering machine behind.
            try? await backend.stopMachine(id: machineName)
            try? await backend.deleteMachine(id: machineName)
            throw error
        }
    }
}
