//
//  RunModelPresetTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class RunModelPresetTests: XCTestCase {
    func testSavePersistsAndApplyLoadsDraftInAFreshModel() throws {
        let store = InMemoryPresetStore()
        let model = RunModel(backend: MockBackend(), taskCenter: TaskCenter(), presetStore: store)
        model.loadPresets()
        XCTAssertTrue(model.runPresets.isEmpty)

        model.draft.image = "nginx:latest"
        model.draft.portRows = ["8080:80"]
        model.savePreset(name: "Web")
        XCTAssertEqual(model.runPresets.count, 1)
        XCTAssertEqual(store.loadRunPresets().first?.name, "Web")

        // A fresh model backed by the same store sees and applies the saved preset.
        let reopened = RunModel(
            backend: MockBackend(), taskCenter: TaskCenter(), presetStore: store)
        reopened.loadPresets()
        let preset = try XCTUnwrap(reopened.runPresets.first)
        reopened.apply(preset)
        XCTAssertEqual(reopened.draft.image, "nginx:latest")
        XCTAssertEqual(reopened.draft.portRows, ["8080:80"])
    }

    func testDeleteRemovesFromModelAndStore() throws {
        let store = InMemoryPresetStore()
        let model = RunModel(backend: MockBackend(), taskCenter: TaskCenter(), presetStore: store)
        model.draft.image = "alpine"
        model.savePreset(name: "A")
        let preset = try XCTUnwrap(model.runPresets.first)
        model.deletePreset(preset)
        XCTAssertTrue(model.runPresets.isEmpty)
        XCTAssertTrue(store.loadRunPresets().isEmpty)
    }
}
