//
//  LanguagePreference.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The user's chosen
//  interface language override. Pure value type; the UI edits it via
//  @AppStorage(LanguagePreference.storageKey) and applies it to the `AppleLanguages` default
//  (which macOS reads at launch, so a change takes effect after relaunch).

public enum LanguagePreference: Sendable, Equatable, Hashable {
    /// Follow the system's preferred languages (the default).
    case system
    /// Force a specific BCP-47 language code (e.g. "ja", "zh-Hans").
    case language(code: String)

    /// The single UserDefaults key shared by the settings UI and the launch-time application.
    public static let storageKey = "capsule.appLanguage"

    /// BCP-47 codes for the localizations Capsule ships, in the order shown in the picker.
    /// The source language ("en") comes first.
    public static let supportedCodes = ["en", "zh-Hans", "ja", "es", "fr", "tr"]

    /// Stable string for UserDefaults.
    public var storageValue: String {
        switch self {
        case .system: return "system"
        case let .language(code): return code
        }
    }

    /// The forced language code, or nil when following the system.
    public var languageCode: String? {
        if case let .language(code) = self { return code }
        return nil
    }

    /// Decodes stored text, treating empty/"system" as `.system`.
    public init(storage: String) {
        if storage.isEmpty || storage == "system" {
            self = .system
        } else {
            self = .language(code: storage)
        }
    }
}
