//
//  BuildModelPresetTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class BuildModelPresetTests: XCTestCase {
    func testSavePersistsContextDirectoryAndApplyLoadsDraft() throws {
        let store = InMemoryPresetStore()
        let model = BuildModel(backend: MockBackend(), taskCenter: TaskCenter(), presetStore: store)
        model.loadPresets()
        XCTAssertTrue(model.buildPresets.isEmpty)

        model.draft.contextDirectory = URL(fileURLWithPath: "/tmp/project")
        model.draft.tag = "app:dev"
        model.savePreset(name: "App")
        XCTAssertEqual(store.loadBuildPresets().first?.name, "App")

        let reopened = BuildModel(
            backend: MockBackend(), taskCenter: TaskCenter(), presetStore: store)
        reopened.loadPresets()
        let preset = try XCTUnwrap(reopened.buildPresets.first)
        reopened.apply(preset)
        XCTAssertEqual(reopened.draft.contextDirectory?.path, "/tmp/project")
        XCTAssertEqual(reopened.draft.tag, "app:dev")
    }

    func testDeleteRemovesFromStore() throws {
        let store = InMemoryPresetStore()
        let model = BuildModel(backend: MockBackend(), taskCenter: TaskCenter(), presetStore: store)
        model.draft.tag = "t:1"
        model.savePreset(name: "B")
        let preset = try XCTUnwrap(model.buildPresets.first)
        model.deletePreset(preset)
        XCTAssertTrue(store.loadBuildPresets().isEmpty)
    }
}
