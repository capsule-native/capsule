//
//  CapsuleErrorTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class CapsuleErrorTests: XCTestCase {
    // MARK: - RecoveryAction / PermissionKind

    func testRecoveryActionsHaveTitles() {
        XCTAssertFalse(RecoveryAction.retry.title.isEmpty)
        XCTAssertFalse(RecoveryAction.retryInTerminal(command: ["container", "ls"]).title.isEmpty)
        XCTAssertFalse(RecoveryAction.startServices.title.isEmpty)
        XCTAssertFalse(RecoveryAction.openLogs.title.isEmpty)
        XCTAssertFalse(RecoveryAction.editConfiguration.title.isEmpty)
        XCTAssertFalse(RecoveryAction.exportDiagnostics.title.isEmpty)
        XCTAssertFalse(RecoveryAction.grantPermission(.administrator).title.isEmpty)
    }

    func testPermissionKindsHaveTitles() {
        XCTAssertFalse(PermissionKind.administrator.title.isEmpty)
        XCTAssertFalse(PermissionKind.fileAccess.title.isEmpty)
        XCTAssertFalse(PermissionKind.network.title.isEmpty)
    }

    // MARK: - ErrorDetail mapping

    func testCommandFailedProducesActionableDetail() {
        let error = CapsuleError.commandFailed(
            command: ["container", "start", "web"],
            exitCode: 1,
            stderr: "Error: no such container: web"
        )
        let detail = error.detail

        XCTAssertFalse(detail.title.isEmpty)
        XCTAssertTrue(detail.explanation.contains("no such container"))
        XCTAssertFalse(detail.recoveryActions.isEmpty, "a failed command must offer recovery steps")
        // The exact failing command is offered for a terminal retry.
        XCTAssertTrue(
            detail.recoveryActions.contains(
                .retryInTerminal(command: ["container", "start", "web"])
            )
        )
    }

    func testCommandFailedWithEmptyStderrStillExplains() {
        let error = CapsuleError.commandFailed(
            command: ["container", "ls"], exitCode: 2, stderr: "")
        let detail = error.detail
        XCTAssertFalse(detail.explanation.isEmpty)
        XCTAssertTrue(detail.explanation.contains("2"), "exit code surfaces when stderr is empty")
    }

    func testDaemonUnavailableUsesProvidedRecovery() {
        let error = CapsuleError.daemonUnavailable(
            message: "The container service is not running.",
            recovery: [.startServices]
        )
        let detail = error.detail
        XCTAssertEqual(detail.explanation, "The container service is not running.")
        XCTAssertEqual(detail.recoveryActions, [.startServices])
    }

    func testDaemonUnavailableFallsBackWhenNoRecoveryGiven() {
        let error = CapsuleError.daemonUnavailable(message: "down", recovery: [])
        XCTAssertTrue(error.detail.recoveryActions.contains(.startServices))
    }

    func testPermissionRequiredOffersGrant() {
        let error = CapsuleError.permissionRequired(
            kind: .administrator,
            message: "Administrator rights are required."
        )
        XCTAssertTrue(error.detail.recoveryActions.contains(.grantPermission(.administrator)))
    }

    func testInvalidInputDetailNamesField() {
        let error = CapsuleError.invalidInput(field: "name", message: "must not be empty")
        let detail = error.detail
        XCTAssertTrue(detail.explanation.contains("name"))
        XCTAssertTrue(detail.explanation.contains("must not be empty"))
    }

    func testInterruptedDetailMentionsSignal() {
        let detail = CapsuleError.interrupted(signal: ProcessSignal.interrupt.rawValue).detail
        XCTAssertFalse(detail.title.isEmpty)
        XCTAssertFalse(detail.recoveryActions.isEmpty)
    }

    func testUnsupportedFeatureDetail() {
        let detail = CapsuleError.unsupportedFeature(message: "Volumes are not supported yet.")
            .detail
        XCTAssertEqual(detail.explanation, "Volumes are not supported yet.")
    }

    func testErrorDetailBridgesToDiagnosticInfo() {
        let detail = ErrorDetail(title: "Boom", explanation: "It broke", recoveryActions: [.retry])
        XCTAssertEqual(detail.diagnosticInfo.summary, "Boom")
        XCTAssertEqual(detail.diagnosticInfo.detail, "It broke")
    }

    // MARK: - CapsuleError.status

    func testInterruptedErrorResolvesToInterruptedByUser() {
        XCTAssertEqual(
            CapsuleError.interrupted(signal: ProcessSignal.interrupt.rawValue).status,
            .interruptedByUser
        )
        XCTAssertEqual(
            CapsuleError.interrupted(signal: ProcessSignal.terminate.rawValue).status,
            .interruptedByUser
        )
    }

    func testCommandFailedWithInterruptExitCodeResolvesToInterruptedByUser() {
        let error = CapsuleError.commandFailed(
            command: ["container", "run"], exitCode: 130, stderr: "")
        XCTAssertEqual(error.status, .interruptedByUser)
    }

    func testCommandFailedResolvesToFailedDuringExecution() {
        let error = CapsuleError.commandFailed(
            command: ["container", "run"], exitCode: 1, stderr: "x")
        XCTAssertEqual(error.status, .failedDuringExecution)
    }

    func testDaemonUnavailableResolvesToBackendUnavailable() {
        XCTAssertEqual(
            CapsuleError.daemonUnavailable(message: "down", recovery: []).status,
            .backendUnavailable
        )
    }

    func testInvalidInputResolvesToFailedBeforeExecution() {
        XCTAssertEqual(
            CapsuleError.invalidInput(field: "n", message: "bad").status,
            .failedBeforeExecution
        )
    }

    func testCapsuleErrorIsEquatable() {
        XCTAssertEqual(
            CapsuleError.interrupted(signal: 2),
            CapsuleError.interrupted(signal: 2)
        )
        XCTAssertNotEqual(
            CapsuleError.interrupted(signal: 2),
            CapsuleError.interrupted(signal: 15)
        )
    }
}
