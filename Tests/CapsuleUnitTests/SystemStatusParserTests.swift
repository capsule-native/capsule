//
//  SystemStatusParserTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleCLIBackend

final class SystemStatusParserTests: XCTestCase {
    func testRunningLineIsRunning() {
        XCTAssertEqual(
            SystemStatusParser.parse(stdout: "apiserver is running", stderr: ""), .running)
    }

    func testNotRunningLineIsStopped() {
        XCTAssertEqual(
            SystemStatusParser.parse(stdout: "apiserver is not running", stderr: ""), .stopped)
    }

    func testEmptyOutputIsStopped() {
        XCTAssertEqual(SystemStatusParser.parse(stdout: "", stderr: ""), .stopped)
    }

    func testStoppedWordIsStopped() {
        XCTAssertEqual(SystemStatusParser.parse(stdout: "Stopped", stderr: ""), .stopped)
    }

    func testRunningReportedOnStderrIsRunning() {
        XCTAssertEqual(
            SystemStatusParser.parse(stdout: "", stderr: "service running"), .running)
    }
}
