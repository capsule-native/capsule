//
//  CapsuleAutomationPackage.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Xcode 26 discovers App Intents that live in a static SwiftPM library only when the
//  library declares an `AppIntentsPackage` and the app references it via `includedPackages`.
//  Without this, the intents compile but never appear in Shortcuts/Siri.
//

import AppIntents

/// Marker package that lets the app's `AppIntentsPackage` pull this library's intents into
/// the App Intents metadata the system extracts at build time.
public struct CapsuleAutomationPackage: AppIntentsPackage {
    public init() {}
}
