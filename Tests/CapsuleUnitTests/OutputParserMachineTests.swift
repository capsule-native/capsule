//
//  OutputParserMachineTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
import XCTest

@testable import CapsuleBackend
@testable import CapsuleCLIBackend

final class OutputParserMachineTests: XCTestCase {
    func test_parseMachines_listShape() throws {
        let json = """
            [{"name":"dev","state":"running","cpus":4,"memory":"8G","disk":"20G",
              "ipAddress":"192.168.66.2","default":true}]
            """
        let rows = try OutputParser.parseMachines(Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "dev")
        XCTAssertEqual(rows[0].cpus, 4)
        XCTAssertTrue(rows[0].isDefault)
    }
    func test_parseMachines_dropsUnnamed_keepsValid() throws {
        let json = #"[{"state":"running"},{"name":"ok"}]"#
        XCTAssertEqual(try OutputParser.parseMachines(Data(json.utf8)).map(\.name), ["ok"])
    }
    func test_parseMachine_single() throws {
        let json = #"{"name":"dev","state":"running"}"#
        XCTAssertEqual(OutputParser.parseMachine(Data(json.utf8))?.name, "dev")
    }
}
