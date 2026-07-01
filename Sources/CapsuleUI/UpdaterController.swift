//
//  UpdaterController.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Lives in the UI layer (not the composition root) so BOTH the menu command and the
//  Preferences “Updates” surface can bind to it. The concrete Sparkle-backed implementation
//  (`SparkleUpdaterController`) lives in `CapsuleApp` and is the only place that imports
//  Sparkle — this protocol stays Sparkle-free so `swift test` and every library target build
//  without it.

import Foundation

/// Abstraction over the software updater (the “Sparkle slot”).
///
/// Class-bound so the settable `automaticallyChecksForUpdates` mutates through the reference
/// when held as an `any UpdaterController` in a `let` (as the composition root does).
@MainActor
public protocol UpdaterController: AnyObject, Sendable {
    /// Whether a manual check can be started right now (false while a check is in flight, or
    /// when no updater is wired).
    var canCheckForUpdates: Bool { get }
    /// The user's automatic-update-check preference. Persisted by the concrete updater.
    var automaticallyChecksForUpdates: Bool { get set }
    /// When the last update check completed, if ever.
    var lastUpdateCheckDate: Date? { get }
    /// Begin a user-initiated update check (shows the updater's own UI).
    func checkForUpdates()
}

/// A do-nothing updater. Used by `AppEnvironment.live()` (so unit tests never instantiate
/// Sparkle) and by SwiftUI previews. The real app injects `SparkleUpdaterController` at launch.
@MainActor
public final class NoopUpdaterController: UpdaterController {
    public init() {}

    public var canCheckForUpdates: Bool { false }
    public var automaticallyChecksForUpdates: Bool = false
    public var lastUpdateCheckDate: Date? { nil }

    public func checkForUpdates() {
        // Intentionally empty — no updater is wired in this environment.
    }
}
