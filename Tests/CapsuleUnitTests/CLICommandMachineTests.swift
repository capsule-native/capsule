//
//  CLICommandMachineTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
import XCTest

@testable import CapsuleBackend

final class CLICommandMachineTests: XCTestCase {
    func test_create_delegatesToConfig() {
        let cfg = MachineConfiguration(image: "alpine:3.22", name: "dev")
        XCTAssertEqual(CLICommand.createMachine(cfg), cfg.arguments)
    }
    func test_set_delegatesToSettings() {
        let s = MachineSettings(cpus: 4)
        XCTAssertEqual(CLICommand.setMachine(name: "dev", settings: s), s.arguments(name: "dev"))
    }
    func test_setDefault_stop_delete_inspect() {
        XCTAssertEqual(CLICommand.setDefaultMachine(id: "dev"), ["machine", "set-default", "dev"])
        XCTAssertEqual(CLICommand.stopMachine(id: "dev"), ["machine", "stop", "dev"])
        XCTAssertEqual(CLICommand.stopMachine(id: nil), ["machine", "stop"])
        XCTAssertEqual(CLICommand.deleteMachine(id: "dev"), ["machine", "delete", "dev"])
        XCTAssertEqual(CLICommand.inspectMachine(id: "dev"), ["machine", "inspect", "dev"])
        XCTAssertEqual(CLICommand.inspectMachine(id: nil), ["machine", "inspect"])
    }
    func test_logs_bootFollowTail() {
        XCTAssertEqual(
            CLICommand.machineLogs(id: "dev", tail: 100, boot: true, follow: false),
            ["machine", "logs", "--boot", "-n", "100", "dev"])
        XCTAssertEqual(
            CLICommand.machineLogs(id: nil, tail: nil, boot: false, follow: true),
            ["machine", "logs", "--follow"])
    }
}
