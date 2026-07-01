//
//  ListContainersIntent.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import AppIntents

/// Lists container names (or ids), optionally including stopped ones.
public struct ListContainersIntent: AppIntent {
    public static let title: LocalizedStringResource = "List Containers"
    public static let description = IntentDescription(
        "Lists container names, optionally including stopped containers.",
        categoryName: "Containers")

    @Parameter(title: "Include Stopped", default: true)
    public var includeStopped: Bool

    public init() {}

    public init(includeStopped: Bool = true) {
        self.includeStopped = includeStopped
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[String]>
        & ProvidesDialog
    {
        let names = try await AutomationRuntime.requireService().listContainers(all: includeStopped)
        return .result(value: names, dialog: "Found ^[\(names.count) container](inflect: true).")
    }
}
