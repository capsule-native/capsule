//
//  CapabilitiesTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Capability probing turns a `BackendVersion` into feature flags so the UI can hide or
//  disable commands a given build (or a not-yet-started system service) cannot serve.

import CapsuleBackend
import XCTest

final class SemanticVersionTests: XCTestCase {
    func testParsesPlainVersion() {
        XCTAssertEqual(SemanticVersion(parsing: "1.0.0"), SemanticVersion(1, 0, 0))
    }

    func testExtractsVersionFromNoisyServerString() {
        // The real apiserver entry: "container-apiserver version 1.0.0 (build: release, …)"
        XCTAssertEqual(
            SemanticVersion(parsing: "container-apiserver version 1.2.0 (build: release)"),
            SemanticVersion(1, 2, 0)
        )
    }

    func testDefaultsMissingPatchToZeroAndCompares() {
        XCTAssertEqual(SemanticVersion(parsing: "2.5"), SemanticVersion(2, 5, 0))
        XCTAssertLessThan(SemanticVersion(0, 9, 0), SemanticVersion(1, 0, 0))
        XCTAssertGreaterThanOrEqual(SemanticVersion(1, 0, 0), SemanticVersion(1, 0, 0))
    }

    func testReturnsNilForUnparseableString() {
        XCTAssertNil(SemanticVersion(parsing: "no version here"))
    }
}

final class BackendCapabilitiesTests: XCTestCase {
    func testRunningSystemExposesAllRuntimeFeatures() {
        let caps = BackendCapabilities.derive(
            from: BackendVersion(client: "1.0.0", server: "apiserver 1.0.0")
        )

        XCTAssertTrue(caps.supports(.containers))
        XCTAssertTrue(caps.supports(.images))
        XCTAssertTrue(caps.supports(.builder))
        XCTAssertTrue(caps.supports(.logsFollow))
        XCTAssertTrue(caps.isSystemRunning)
    }

    func testClientOnlyHidesRuntimeFeaturesButKeepsSystem() {
        let caps = BackendCapabilities.derive(from: BackendVersion(client: "1.0.0", server: nil))

        XCTAssertTrue(caps.supports(.system))
        XCTAssertFalse(caps.supports(.containers))
        XCTAssertFalse(caps.isSystemRunning)
    }

    func testOldClientHidesEvenWhenSystemRunning() {
        let caps = BackendCapabilities.derive(
            from: BackendVersion(client: "0.9.0", server: "apiserver 0.9.0")
        )

        XCTAssertFalse(caps.supports(.containers))
        XCTAssertFalse(caps.supports(.system))
    }
}
