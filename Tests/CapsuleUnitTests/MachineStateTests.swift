//
//  MachineStateTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest
@testable import CapsuleDomain

final class MachineStateTests: XCTestCase {
    func test_parsing() {
        XCTAssertEqual(MachineState(raw: "running"), .running)
        XCTAssertEqual(MachineState(raw: "RUNNING"), .running)
        XCTAssertEqual(MachineState(raw: "stopped"), .stopped)
        XCTAssertEqual(MachineState(raw: nil), .unknown)
        XCTAssertEqual(MachineState(raw: "weird"), .unknown)
    }
    func test_isRunning_label() {
        XCTAssertTrue(MachineState.running.isRunning)
        XCTAssertEqual(MachineState.stopped.label, "Stopped")
    }
}
