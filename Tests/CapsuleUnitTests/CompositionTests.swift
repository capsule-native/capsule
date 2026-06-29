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

    @MainActor
    func testLiveEnvironmentBuildsBrowserModel() {
        let environment = AppEnvironment.live()

        XCTAssertEqual(environment.browserModel.loadState, .idle)
        XCTAssertTrue(environment.browserModel.allContainers.isEmpty)
    }

    @MainActor
    func testLiveEnvironmentBuildsLifecycleAndStatsModels() {
        let environment = AppEnvironment.live()

        XCTAssertTrue(environment.lifecycleModel.busy.isEmpty)
        XCTAssertNil(environment.lifecycleModel.attachSession)
        XCTAssertNil(environment.lifecycleModel.notice)
        XCTAssertTrue(environment.statsModel.metrics.isEmpty)
    }

    @MainActor
    func testLiveEnvironmentExposesM7Models() {
        let environment = AppEnvironment.live()

        // Run/Build/Copy share the single TaskCenter so their jobs land in the Activity pane.
        XCTAssertTrue(environment.runModel.draft.image.isEmpty)
        XCTAssertTrue(environment.buildModel.draft.tag.isEmpty)
        XCTAssertNil(environment.logsModel.containerID)
        XCTAssertEqual(environment.copyModel.direction, .toContainer)
        XCTAssertTrue(environment.taskCenter.tasks.isEmpty)
    }

    @MainActor
    func testLiveEnvironmentExposesVolumeModels() {
        let environment = AppEnvironment.live()

        XCTAssertEqual(environment.volumeBrowserModel.loadState, .idle)
        XCTAssertTrue(environment.volumeBrowserModel.allVolumes.isEmpty)
        XCTAssertTrue(environment.volumeActionsModel.busy.isEmpty)
        XCTAssertNil(environment.volumeActionsModel.notice)
    }
}
