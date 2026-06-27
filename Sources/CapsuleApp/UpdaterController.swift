//
//  UpdaterController.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// Abstraction over the software updater.
///
/// This is the Sparkle "slot": the concrete Sparkle-backed implementation is dropped in
/// during the distribution milestone without touching the rest of the app. Milestone 1
/// ships a no-op.
@MainActor
public protocol UpdaterController: Sendable {
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
}

/// A do-nothing updater used until Sparkle is wired in.
public struct NoopUpdaterController: UpdaterController {
    public init() {}

    public var canCheckForUpdates: Bool { false }

    public func checkForUpdates() {
        // Sparkle wiring goes here.
    }
}
