//
//  BuildImageIntent.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import AppIntents
import Foundation

/// Builds an image from a build-context folder and a tag.
public struct BuildImageIntent: AppIntent {
    public static let title: LocalizedStringResource = "Build Image"
    public static let description = IntentDescription(
        "Builds an image from a build-context folder.",
        categoryName: "Images")

    @Parameter(title: "Context Folder", description: "Path to the build-context directory.")
    public var contextPath: String

    @Parameter(title: "Tag", description: "The image tag to apply, e.g. myapp:latest.")
    public var tag: String

    public init() {}

    public init(contextPath: String, tag: String) {
        self.contextPath = contextPath
        self.tag = tag
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Build \(\.$tag) from \(\.$contextPath)")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await AutomationRuntime.requireService().buildImage(
            contextDirectory: URL(fileURLWithPath: contextPath), tag: tag)
        return .result(dialog: "Built \(tag).")
    }
}
