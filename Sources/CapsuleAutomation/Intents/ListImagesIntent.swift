//
//  ListImagesIntent.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import AppIntents

/// Lists local image references.
public struct ListImagesIntent: AppIntent {
    public static let title: LocalizedStringResource = "List Images"
    public static let description = IntentDescription(
        "Lists the references of local images.",
        categoryName: "Images")

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<[String]>
        & ProvidesDialog
    {
        let references = try await AutomationRuntime.requireService().listImages()
        return .result(
            value: references, dialog: "Found ^[\(references.count) image](inflect: true).")
    }
}
