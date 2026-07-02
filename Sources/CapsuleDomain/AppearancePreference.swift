//
//  AppearancePreference.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The user's chosen
//  window appearance. Pure value type; the UI edits it via
//  @AppStorage(AppearancePreference.storageKey) and maps it to a SwiftUI ColorScheme.

public enum AppearancePreference: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Follow the system's Light/Dark setting (the default).
    case system
    case light
    case dark

    /// The single UserDefaults key shared by the settings UI and the appearance modifier.
    public static let storageKey = "capsule.appearance"

    /// Stable string for UserDefaults.
    public var storageValue: String { rawValue }

    /// Decodes stored text, falling back to `.system` for anything unrecognized.
    public init(storage: String) {
        self = AppearancePreference(rawValue: storage) ?? .system
    }
}
