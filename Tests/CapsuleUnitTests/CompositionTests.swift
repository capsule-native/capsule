//
//  CompositionTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import XCTest

@testable import CapsuleApp

final class CompositionTests: XCTestCase {
    @MainActor
    func testLiveEnvironmentWiresWorkspaceAndUpdater() {
        let environment = AppEnvironment.live()

        XCTAssertEqual(environment.workspaceModel.loadState, .idle)
        XCTAssertFalse(environment.updater.canCheckForUpdates)
    }

    @MainActor
    func testLiveEnvironmentBuildsSystemModelInUnknownState() {
        let environment = AppEnvironment.live()

        XCTAssertEqual(environment.systemModel.health, .unknown)
    }
}
