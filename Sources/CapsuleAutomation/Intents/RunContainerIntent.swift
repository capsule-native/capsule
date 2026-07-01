//
//  RunContainerIntent.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import AppIntents

/// Runs a detached container from an image reference and returns the new container id.
public struct RunContainerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Run Container"
    public static let description = IntentDescription(
        "Runs a detached container from an image.",
        categoryName: "Containers")

    @Parameter(title: "Image", description: "The image reference to run, e.g. nginx:latest.")
    public var image: String

    @Parameter(title: "Name", description: "An optional name for the new container.")
    public var name: String?

    public init() {}

    public init(image: String, name: String? = nil) {
        self.image = image
        self.name = name
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$image)")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog
    {
        let id = try await AutomationRuntime.requireService().runContainer(image: image, name: name)
        return .result(value: id, dialog: "Started container \(id).")
    }
}
