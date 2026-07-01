//
//  UpdaterControllerTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Exercises the `UpdaterController` seam without Sparkle: the no-op controller's defaults and
//  the get/set contract every conformer (including SparkleUpdaterController) must satisfy.

import CapsuleUI
import XCTest

/// A minimal in-memory `UpdaterController` proving the settable-through-reference contract.
@MainActor
private final class StubUpdaterController: UpdaterController {
    var canCheckForUpdates = true
    var automaticallyChecksForUpdates = false
    var lastUpdateCheckDate: Date?
    private(set) var checkCount = 0

    func checkForUpdates() { checkCount += 1 }
}

final class UpdaterControllerTests: XCTestCase {
    @MainActor
    func testNoopDefaultsAreInert() {
        let updater = NoopUpdaterController()
        XCTAssertFalse(updater.canCheckForUpdates)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        XCTAssertNil(updater.lastUpdateCheckDate)
        // Must be safe to call — it just does nothing.
        updater.checkForUpdates()
    }

    @MainActor
    func testNoopAutomaticCheckSetterDoesNotCrash() {
        let updater = NoopUpdaterController()
        updater.automaticallyChecksForUpdates = true
        // No assertion on the value: the no-op need not persist it, only tolerate the write
        // (the Preferences toggle binds get/set through `any UpdaterController`).
        updater.automaticallyChecksForUpdates = false
    }

    @MainActor
    func testAutomaticCheckMutatesThroughExistentialReference() {
        // The composition root holds the updater as `any UpdaterController` in a `let`; the
        // Preferences toggle still writes the setting because the protocol is class-bound.
        let updater: any UpdaterController = StubUpdaterController()
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        updater.automaticallyChecksForUpdates = true
        XCTAssertTrue(updater.automaticallyChecksForUpdates)
    }

    @MainActor
    func testCheckForUpdatesInvokesConformer() {
        let stub = StubUpdaterController()
        let updater: any UpdaterController = stub
        updater.checkForUpdates()
        updater.checkForUpdates()
        XCTAssertEqual(stub.checkCount, 2)
    }
}
