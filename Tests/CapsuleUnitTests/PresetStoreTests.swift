//
//  PresetStoreTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class PresetStoreTests: XCTestCase {
    func testInMemoryRunPresetsRoundTrip() {
        let store = InMemoryPresetStore()
        XCTAssertTrue(store.loadRunPresets().isEmpty)
        let presets = [SavedRunPreset(name: "Web", draft: RunDraft(image: "nginx"))]
        store.saveRunPresets(presets)
        XCTAssertEqual(store.loadRunPresets(), presets)
    }

    func testInMemoryBuildPresetsRoundTrip() {
        let store = InMemoryPresetStore()
        XCTAssertTrue(store.loadBuildPresets().isEmpty)
        var draft = BuildDraft()
        draft.tag = "app:dev"
        let presets = [SavedBuildPreset(name: "App", draft: draft)]
        store.saveBuildPresets(presets)
        XCTAssertEqual(store.loadBuildPresets(), presets)
    }

    func testInMemorySeedsInitialPresets() {
        let run = [SavedRunPreset(name: "R", draft: RunDraft())]
        let build = [SavedBuildPreset(name: "B", draft: BuildDraft())]
        let store = InMemoryPresetStore(runPresets: run, buildPresets: build)
        XCTAssertEqual(store.loadRunPresets(), run)
        XCTAssertEqual(store.loadBuildPresets(), build)
    }
}
