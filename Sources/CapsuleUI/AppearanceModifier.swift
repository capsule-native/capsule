//
//  AppearanceModifier.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Applies the user's appearance preference (System/Light/Dark) as a `preferredColorScheme`,
//  read live from @AppStorage so every window follows the Settings ▸ General selection. The
//  terminal and contrast-aware fills already track the environment color scheme, so they follow
//  the override for free.

import CapsuleDomain
import SwiftUI

extension AppearancePreference {
    /// The SwiftUI color scheme to force, or nil to follow the system (`.system`).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private struct AppearanceModifier: ViewModifier {
    @AppStorage(AppearancePreference.storageKey) private var raw =
        AppearancePreference.system.storageValue

    func body(content: Content) -> some View {
        content.preferredColorScheme(AppearancePreference(storage: raw).colorScheme)
    }
}

extension View {
    /// Follow the app-wide appearance preference. Apply at each window scene's root so Light/Dark
    /// overrides reach every window.
    public func capsuleAppearance() -> some View { modifier(AppearanceModifier()) }
}
