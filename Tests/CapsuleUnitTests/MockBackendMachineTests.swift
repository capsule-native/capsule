//
//  MockBackendMachineTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
import XCTest

@testable import CapsuleBackend

final class MockBackendMachineTests: XCTestCase {
    func test_create_appendsAndRecords() async throws {
        let mock = MockBackend(machines: [])
        let cfg = MachineConfiguration(image: "alpine:3.22", name: "dev", setDefault: true)
        for try await _ in mock.createMachine(cfg) {}  // drain the stream
        XCTAssertEqual(mock.lastCreatedMachine, cfg)
        let list = try await mock.listMachines()
        XCTAssertEqual(list.map(\.name), ["dev"])
        XCTAssertTrue(list[0].isDefault)
    }

    func test_setDefault_flipsExclusive() async throws {
        let mock = MockBackend(machines: [
            MachineSummary(name: "a", isDefault: true), MachineSummary(name: "b"),
        ])
        try await mock.setDefaultMachine(id: "b")
        XCTAssertEqual(mock.lastSetDefaultID, "b")
        let list = try await mock.listMachines()
        XCTAssertEqual(Set(list.filter(\.isDefault).map(\.name)), ["b"])
    }

    func test_set_recordsAndApplies() async throws {
        let mock = MockBackend(machines: [MachineSummary(name: "dev", cpus: 2)])
        try await mock.setMachine(name: "dev", settings: MachineSettings(cpus: 8, memory: "16G"))
        XCTAssertEqual(mock.lastMachineSettings?.settings.cpus, 8)
        let dev = try await mock.listMachines().first { $0.name == "dev" }
        XCTAssertEqual(dev?.cpus, 8)
        XCTAssertEqual(dev?.memory, "16G")
    }

    func test_stop_thenDelete() async throws {
        let mock = MockBackend(machines: [MachineSummary(name: "dev", state: "running")])
        try await mock.stopMachine(id: "dev")
        XCTAssertEqual(mock.lastStoppedMachine, "dev")
        let stoppedState = try await mock.listMachines().first?.state
        XCTAssertEqual(stoppedState, "stopped")
        try await mock.deleteMachine(id: "dev")
        XCTAssertEqual(mock.lastDeletedMachine, "dev")
        let remainingCount = try await mock.listMachines().count
        XCTAssertEqual(remainingCount, 0)
    }

    func test_inspect_defaultWhenNil() async throws {
        let mock = MockBackend(machines: [
            MachineSummary(name: "a"), MachineSummary(name: "b", isDefault: true),
        ])
        let parsed = try await mock.inspectMachine(id: nil)
        XCTAssertEqual(parsed.value?.name, "b")  // default
        let byId = try await mock.inspectMachine(id: "a")
        XCTAssertEqual(byId.value?.name, "a")
    }

    func test_machineLogs_bootRespectsTail() async throws {
        let mock = MockBackend(machines: [MachineSummary(name: "dev")])
        let lines = try await mock.fetchMachineLogs(id: "dev", tail: 1, boot: true)
        XCTAssertEqual(lines.count, 1)
    }

    func test_sampleMachines_hasDefault() {
        XCTAssertTrue(MockBackend.sampleMachines.contains { $0.isDefault })
    }
}
