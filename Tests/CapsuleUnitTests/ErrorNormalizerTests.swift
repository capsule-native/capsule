//
//  ErrorNormalizerTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import CapsuleDomain
import XCTest

@testable import CapsuleDiagnostics

private struct SampleLocalizedError: LocalizedError {
    var errorDescription: String? { "a localized message" }
}

private struct SampleOpaqueError: Error {}

final class ErrorNormalizerTests: XCTestCase {
    func testNormalizePassesThroughCapsuleError() {
        let original = CapsuleError.invalidInput(field: "name", message: "empty")
        XCTAssertEqual(ErrorNormalizer.normalize(original), original)
    }

    func testNormalizeWrapsLocalizedErrorMessage() {
        let normalized = ErrorNormalizer.normalize(SampleLocalizedError())
        XCTAssertEqual(normalized, .unknown(message: "a localized message"))
    }

    func testNormalizeWrapsOpaqueError() {
        let normalized = ErrorNormalizer.normalize(SampleOpaqueError())
        guard case let .unknown(message) = normalized else {
            return XCTFail("expected .unknown, got \(normalized)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testDetailForCapsuleErrorIsActionable() {
        let error = CapsuleError.commandFailed(
            command: ["container", "ls"],
            exitCode: 1,
            stderr: "boom"
        )
        let detail = ErrorNormalizer.detail(for: error)
        XCTAssertEqual(detail.title, "Command failed")
        XCTAssertFalse(detail.recoveryActions.isEmpty)
    }

    func testDetailForOpaqueErrorOffersLogsAndExport() {
        let detail = ErrorNormalizer.detail(for: SampleOpaqueError())
        XCTAssertTrue(detail.recoveryActions.contains(.openLogs))
        XCTAssertTrue(detail.recoveryActions.contains(.exportDiagnostics))
    }

    func testDiagnosticInfoBridge() {
        let info = ErrorNormalizer.diagnosticInfo(for: SampleLocalizedError())
        XCTAssertEqual(info.summary, "Something went wrong")
        XCTAssertEqual(info.detail, "a localized message")
    }

    // MARK: - BackendError mapping

    func testNonZeroExitWithDaemonSignatureBecomesDaemonUnavailable() {
        let error = BackendError.nonZeroExit(
            command: "container system status", code: 1, stderr: "Connection refused")
        guard case let .daemonUnavailable(_, recovery) = ErrorNormalizer.normalize(error) else {
            return XCTFail("expected .daemonUnavailable")
        }
        XCTAssertTrue(recovery.contains(.startServices))
        XCTAssertTrue(recovery.contains(.openLogs))
    }

    func testNonZeroExitWithXPCSignatureBecomesDaemonUnavailable() {
        let error = BackendError.nonZeroExit(
            command: "container system start", code: 1,
            stderr: "failed to connect to XPC service")
        guard case .daemonUnavailable = ErrorNormalizer.normalize(error) else {
            return XCTFail("expected .daemonUnavailable for an XPC failure")
        }
    }

    func testNonZeroExitWithoutDaemonSignatureBecomesCommandFailed() {
        let error = BackendError.nonZeroExit(
            command: "container image delete alpine", code: 2, stderr: "no such image")
        guard case let .commandFailed(command, exitCode, stderr) = ErrorNormalizer.normalize(error)
        else {
            return XCTFail("expected .commandFailed")
        }
        XCTAssertEqual(command, ["container", "image", "delete", "alpine"])
        XCTAssertEqual(exitCode, 2)
        XCTAssertEqual(stderr, "no such image")
    }

    func testExecutableNotFoundBecomesDaemonUnavailable() {
        let error = BackendError.executableNotFound("/usr/local/bin/container")
        guard case let .daemonUnavailable(message, recovery) = ErrorNormalizer.normalize(error)
        else {
            return XCTFail("expected .daemonUnavailable")
        }
        XCTAssertTrue(message.contains("/usr/local/bin/container"))
        XCTAssertTrue(recovery.contains(.exportDiagnostics))
    }

    func testDecodingFailedBecomesUnknown() {
        let error = BackendError.decodingFailed("bad json")
        XCTAssertEqual(ErrorNormalizer.normalize(error), .unknown(message: "bad json"))
    }
}
