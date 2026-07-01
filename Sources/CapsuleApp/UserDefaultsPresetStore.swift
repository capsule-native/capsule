//
//  UserDefaultsPresetStore.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The concrete `PresetStore` for saved Run/Build presets. It lives in the composition root
//  (not the domain) so the persistence keys and JSON encoding stay out of `CapsuleDomain`.

import CapsuleDomain
import Foundation

struct UserDefaultsPresetStore: PresetStore {
    // `UserDefaults` is thread-safe but not yet `Sendable`-annotated; the store conforms
    // to the `Sendable` `PresetStore` seam, so opt the reference out of the check.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let runKey = "capsule.runPresets"
    private let buildKey = "capsule.buildPresets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadRunPresets() -> [SavedRunPreset] {
        guard
            let data = defaults.data(forKey: runKey),
            let presets = try? JSONDecoder().decode([SavedRunPreset].self, from: data)
        else {
            return []
        }
        return presets
    }

    func saveRunPresets(_ presets: [SavedRunPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: runKey)
    }

    func loadBuildPresets() -> [SavedBuildPreset] {
        guard
            let data = defaults.data(forKey: buildKey),
            let presets = try? JSONDecoder().decode([SavedBuildPreset].self, from: data)
        else {
            return []
        }
        return presets
    }

    func saveBuildPresets(_ presets: [SavedBuildPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: buildKey)
    }
}
