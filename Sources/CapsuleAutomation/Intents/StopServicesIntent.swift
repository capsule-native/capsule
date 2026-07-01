//
//  StopServicesIntent.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import AppIntents

/// Stops the container system service from Shortcuts / Siri.
public struct StopServicesIntent: AppIntent {
    public static let title: LocalizedStringResource = "Stop Container Services"
    public static let description = IntentDescription(
        "Stops Capsule's container system service.",
        categoryName: "System")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AutomationRuntime.requireService().stopServices()
        return .result(dialog: "Stopped the container services.")
    }
}
