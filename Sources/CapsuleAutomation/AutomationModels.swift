//
//  AutomationModels.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import Foundation

/// A `Sendable`, shortcut-facing description of an action Capsule can perform.
///
/// App Intents and AppleScript terminology will wrap these in a later milestone; the
/// models are defined here so automation surfaces share one vocabulary.
public struct AutomationCommand: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var resourceKind: ResourceKind

    public init(id: String, title: String, resourceKind: ResourceKind) {
        self.id = id
        self.title = title
        self.resourceKind = resourceKind
    }
}

extension AutomationCommand {
    public static let listContainers = AutomationCommand(
        id: "list-containers",
        title: "List Containers",
        resourceKind: .container
    )

    public static let listImages = AutomationCommand(
        id: "list-images",
        title: "List Images",
        resourceKind: .image
    )
}

// MARK: - App Intents slot
//
// TODO (later milestone): conform an `AppIntent` per `AutomationCommand` and register
// an `AppShortcutsProvider`. Kept dependency-free here so the module builds without an
// app bundle context.

// MARK: - AppleScript terminology slot
//
// TODO (later milestone): ship an `.sdef` terminology file and `NSScriptCommand`
// handlers mapping to the automation commands above.
