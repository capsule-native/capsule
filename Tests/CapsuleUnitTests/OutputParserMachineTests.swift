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
    // Real `container machine list --format json` captured 2026-06-29.
    func test_parseMachines_listShape() throws {
        let json = """
            [{"memory":2147483648,"default":true,"ipAddress":"192.168.64.9",
              "id":"capsule-probe","createdDate":"2026-06-29T20:03:11Z",
              "status":"running","cpus":2,"diskSize":78643200}]
            """
        let rows = try OutputParser.parseMachines(Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        let m = rows[0]
        XCTAssertEqual(m.name, "capsule-probe")  // id → name
        XCTAssertEqual(m.state, "running")  // status → state
        XCTAssertEqual(m.cpus, 2)
        XCTAssertTrue(m.isDefault)
        XCTAssertEqual(m.memory, "2G")  // 2147483648 bytes → "2G"
        XCTAssertEqual(m.disk, "75M")  // 78643200 bytes → "75M"
        XCTAssertEqual(m.ipAddress, "192.168.64.9")
    }

    // A record without `id` is silently dropped; one with `id` is kept.
    func test_parseMachines_dropsUnnamed_keepsValid() throws {
        let json = #"[{"status":"running"},{"id":"ok"}]"#
        XCTAssertEqual(try OutputParser.parseMachines(Data(json.utf8)).map(\.name), ["ok"])
    }

    // Real `container machine inspect` emits an ARRAY of one object.
    func test_parseMachine_single() throws {
        let json = #"[{"id":"dev","status":"running"}]"#
        let m = OutputParser.parseMachine(Data(json.utf8))
        XCTAssertEqual(m?.name, "dev")
        XCTAssertEqual(m?.state, "running")
    }
}
