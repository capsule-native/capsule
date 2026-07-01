//
//  SparkleUpdaterController.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The ONE file that imports Sparkle. It fills the `UpdaterController` seam (defined in
//  CapsuleUI) with a real, unsandboxed Sparkle updater. The feed URL, EdDSA public key, and
//  automatic-check defaults come from the app bundle's Info.plist (SUFeedURL / SUPublicEDKey /
//  SUEnableAutomaticChecks). Instantiated only from `CapsuleScene.init()` — never in unit
//  tests — so `swift test` never spins up the updater.

import CapsuleUI
import Foundation
import Sparkle

/// A Sparkle-backed `UpdaterController` for the unsandboxed, Developer-ID-signed build.
///
/// Uses `SPUStandardUpdaterController`, which owns an `SPUUpdater` and the standard user
/// driver (the familiar “A new version is available” panel). No XPC services are needed
/// because the app is unsandboxed.
@MainActor
public final class SparkleUpdaterController: UpdaterController {
    private let controller: SPUStandardUpdaterController

    /// - Parameter startsUpdater: start the background updater immediately (the production
    ///   default). Passing `false` constructs the controller without scheduling checks.
    public init(startsUpdater: Bool = true) {
        controller = SPUStandardUpdaterController(
            startingUpdater: startsUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    public var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    public var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    public var lastUpdateCheckDate: Date? { controller.updater.lastUpdateCheckDate }

    public func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
