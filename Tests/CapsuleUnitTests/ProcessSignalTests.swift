//
//  ProcessSignalTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class ProcessSignalTests: XCTestCase {
    func testSigintExitCodeIs130() {
        XCTAssertEqual(ProcessSignal.interrupt.rawValue, 2)
        XCTAssertEqual(ProcessSignal.interrupt.exitCode, 130)
    }

    func testSigtermExitCodeIs143() {
        XCTAssertEqual(ProcessSignal.terminate.rawValue, 15)
        XCTAssertEqual(ProcessSignal.terminate.exitCode, 143)
    }

    func testSignalNames() {
        XCTAssertEqual(ProcessSignal.interrupt.name, "SIGINT")
        XCTAssertEqual(ProcessSignal.terminate.name, "SIGTERM")
    }

    func testExitCodeForArbitrarySignalIs128PlusSignal() {
        XCTAssertEqual(ProcessSignal.exitCode(forSignal: 2), 130)
        XCTAssertEqual(ProcessSignal.exitCode(forSignal: 15), 143)
        XCTAssertEqual(ProcessSignal.exitCode(forSignal: 9), 137)
    }

    func testSignalForExitCodeRecoversSignalNumber() {
        XCTAssertEqual(ProcessSignal.signal(forExitCode: 130), 2)
        XCTAssertEqual(ProcessSignal.signal(forExitCode: 143), 15)
        XCTAssertNil(ProcessSignal.signal(forExitCode: 0))
        XCTAssertNil(ProcessSignal.signal(forExitCode: 1))
        XCTAssertNil(ProcessSignal.signal(forExitCode: 128))
    }

    func testIsUserInterruptionRecognizes130And143() {
        XCTAssertTrue(ProcessSignal.isUserInterruption(exitCode: 130))
        XCTAssertTrue(ProcessSignal.isUserInterruption(exitCode: 143))
    }

    func testIsUserInterruptionRejectsOrdinaryExitCodes() {
        XCTAssertFalse(ProcessSignal.isUserInterruption(exitCode: 0))
        XCTAssertFalse(ProcessSignal.isUserInterruption(exitCode: 1))
        XCTAssertFalse(ProcessSignal.isUserInterruption(exitCode: 137))
    }
}
