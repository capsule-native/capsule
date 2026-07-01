//
//  CapsuleShortcuts.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  App Shortcuts + the App Intents package bridge. These live in the app target (always scanned
//  by Xcode's App Intents metadata extractor) while the intent *types* live in the
//  CapsuleAutomation library (listed via APP_INTENTS_MODULE_NAMES and pulled in through the
//  package's `includedPackages`).
//

import AppIntents
import CapsuleAutomation

/// Bridges CapsuleAutomation's App Intents package into the app so the metadata extractor
/// discovers the library's intents at build time.
struct CapsuleAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [CapsuleAutomationPackage.self]
    }
}

/// The App Shortcuts Capsule offers out of the box (visible in the Shortcuts app + Spotlight,
/// and invocable by phrase). Every phrase must contain `\(.applicationName)`.
struct CapsuleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartServicesIntent(),
            phrases: ["Start \(.applicationName) services"],
            shortTitle: "Start Services",
            systemImageName: "play.circle")
        AppShortcut(
            intent: StopServicesIntent(),
            phrases: ["Stop \(.applicationName) services"],
            shortTitle: "Stop Services",
            systemImageName: "stop.circle")
        AppShortcut(
            intent: RunContainerIntent(),
            phrases: ["Run a container with \(.applicationName)"],
            shortTitle: "Run Container",
            systemImageName: "shippingbox")
        AppShortcut(
            intent: PullImageIntent(),
            phrases: ["Pull an image with \(.applicationName)"],
            shortTitle: "Pull Image",
            systemImageName: "arrow.down.circle")
        AppShortcut(
            intent: ReclaimSpaceIntent(),
            phrases: ["Reclaim space with \(.applicationName)"],
            shortTitle: "Reclaim Space",
            systemImageName: "trash")
        AppShortcut(
            intent: ListContainersIntent(),
            phrases: ["List \(.applicationName) containers"],
            shortTitle: "List Containers",
            systemImageName: "list.bullet")
    }
}
