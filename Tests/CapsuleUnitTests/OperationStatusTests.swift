//
//  OperationStatusTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class OperationStatusTests: XCTestCase {
    func testCleanSuccess() {
        let obs = CommandObservation(commandExitCode: 0)
        XCTAssertEqual(OperationStatus.resolve(obs), .succeeded)
    }

    func testSuccessWithWarnings() {
        let obs = CommandObservation(commandExitCode: 0, hasWarnings: true)
        XCTAssertEqual(OperationStatus.resolve(obs), .succeededWithWarnings)
    }

    func testFailureDuringExecution() {
        let obs = CommandObservation(commandExitCode: 1)
        XCTAssertEqual(OperationStatus.resolve(obs), .failedDuringExecution)
    }

    func testFailureBeforeExecution() {
        let obs = CommandObservation(phase: .beforeExecution, commandExitCode: 127)
        XCTAssertEqual(OperationStatus.resolve(obs), .failedBeforeExecution)
    }

    func testBackendUnavailableWins() {
        let obs = CommandObservation(phase: .beforeExecution, backendUnavailable: true)
        XCTAssertEqual(OperationStatus.resolve(obs), .backendUnavailable)
    }

    func testInterruptByExitCode130() {
        let obs = CommandObservation(commandExitCode: 130)
        XCTAssertEqual(OperationStatus.resolve(obs), .interruptedByUser)
    }

    func testInterruptByExitCode143() {
        let obs = CommandObservation(commandExitCode: 143)
        XCTAssertEqual(OperationStatus.resolve(obs), .interruptedByUser)
    }

    func testInterruptBySignalField() {
        let obs = CommandObservation(commandExitCode: 1, signal: ProcessSignal.interrupt.rawValue)
        XCTAssertEqual(OperationStatus.resolve(obs), .interruptedByUser)
    }

    func testInterruptionBeatsBackendUnavailable() {
        let obs = CommandObservation(
            commandExitCode: 130,
            signal: ProcessSignal.interrupt.rawValue,
            backendUnavailable: true
        )
        XCTAssertEqual(OperationStatus.resolve(obs), .interruptedByUser)
    }

    func testStateChangedButAttachmentFailed() {
        // `container start` flipped the container to running, but attaching afterward failed.
        let obs = CommandObservation(
            commandExitCode: 1,
            containerRuntimeState: .running,
            attachmentFailed: true
        )
        XCTAssertEqual(OperationStatus.resolve(obs), .stateChangedButAttachmentFailed)
    }

    func testThreeFieldsAreIndependent() {
        // Command succeeded, but the task inside exited non-zero, and the container is
        // now stopped — the three fields are retained separately rather than collapsed.
        let obs = CommandObservation(
            commandExitCode: 0,
            taskExitCode: 137,
            containerRuntimeState: .stopped
        )
        XCTAssertEqual(obs.commandExitCode, 0)
        XCTAssertEqual(obs.taskExitCode, 137)
        XCTAssertEqual(obs.containerRuntimeState, .stopped)
        // The command itself succeeded; the task's non-zero exit does not flip command status.
        XCTAssertEqual(OperationStatus.resolve(obs), .succeeded)
    }

    func testIsSuccess() {
        XCTAssertTrue(OperationStatus.succeeded.isSuccess)
        XCTAssertTrue(OperationStatus.succeededWithWarnings.isSuccess)
        XCTAssertFalse(OperationStatus.failedDuringExecution.isSuccess)
        XCTAssertFalse(OperationStatus.interruptedByUser.isSuccess)
        XCTAssertFalse(OperationStatus.backendUnavailable.isSuccess)
    }
}
