//
//  StartServicesIntent.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Spike/first real intent — verifies App Intents compile inside the CapsuleAutomation
//  library under plain `swift build` (CLT toolchain, Swift 5 language mode).
//

import AppIntents

/// Starts the container system service from Shortcuts / Siri.
public struct StartServicesIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start Container Services"
    public static let description = IntentDescription(
        "Starts Capsule's container system service.",
        categoryName: "System")

    /// The shared automation facade, registered by the app at launch via
    /// `AppDependencyManager`. Resolving a protocol existential keeps intents testable.
    @Dependency public var service: any AutomationService

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await service.startServices()
        return .result(dialog: "Started the container services.")
    }
}
