//
//  PullImageIntent.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import AppIntents

/// Pulls an image from a registry.
public struct PullImageIntent: AppIntent {
    public static let title: LocalizedStringResource = "Pull Image"
    public static let description = IntentDescription(
        "Pulls an image from a registry.",
        categoryName: "Images")

    @Parameter(title: "Image", description: "The image reference to pull, e.g. nginx:latest.")
    public var reference: String

    @Parameter(title: "Platform", description: "Optional platform, e.g. linux/arm64.")
    public var platform: String?

    public init() {}

    public init(reference: String, platform: String? = nil) {
        self.reference = reference
        self.platform = platform
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Pull \(\.$reference)")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await AutomationRuntime.requireService().pullImage(
            reference: reference, platform: platform)
        return .result(dialog: "Pulled \(reference).")
    }
}
