//
//  UserDefaultsPresetStoreTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import XCTest

@testable import CapsuleApp

final class UserDefaultsPresetStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "capsule.tests.\(UUID().uuidString)")!
    }

    func testRunPresetsPersistAcrossInstances() {
        let defaults = makeDefaults()
        let store = UserDefaultsPresetStore(defaults: defaults)
        XCTAssertTrue(store.loadRunPresets().isEmpty)
        let presets = [SavedRunPreset(name: "Web", draft: RunDraft(image: "nginx"))]
        store.saveRunPresets(presets)
        let reread = UserDefaultsPresetStore(defaults: defaults)
        XCTAssertEqual(reread.loadRunPresets(), presets)
    }

    func testBuildPresetsPersistContextDirectory() {
        let defaults = makeDefaults()
        let store = UserDefaultsPresetStore(defaults: defaults)
        var draft = BuildDraft()
        draft.contextDirectory = URL(fileURLWithPath: "/tmp/project")
        draft.tag = "app:dev"
        store.saveBuildPresets([SavedBuildPreset(name: "App", draft: draft)])
        let reread = UserDefaultsPresetStore(defaults: defaults)
        XCTAssertEqual(
            reread.loadBuildPresets().first?.draft.contextDirectory?.path, "/tmp/project")
    }

    func testCorruptDataFallsBackToEmpty() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "capsule.runPresets")
        let store = UserDefaultsPresetStore(defaults: defaults)
        XCTAssertTrue(store.loadRunPresets().isEmpty)
    }
}
