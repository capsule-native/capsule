//
//  ErrorNormalizerTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

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
}
