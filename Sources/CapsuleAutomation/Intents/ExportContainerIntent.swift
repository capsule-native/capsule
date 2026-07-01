//
//  ExportContainerIntent.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import AppIntents
import Foundation

/// Exports a container's filesystem to a tar archive on disk.
public struct ExportContainerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Export Container"
    public static let description = IntentDescription(
        "Exports a container's filesystem to a tar archive.",
        categoryName: "Containers")

    @Parameter(title: "Container", description: "The container id or name to export.")
    public var container: String

    @Parameter(title: "Destination", description: "Path to write the .tar archive to.")
    public var destinationPath: String

    public init() {}

    public init(container: String, destinationPath: String) {
        self.container = container
        self.destinationPath = destinationPath
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Export \(\.$container) to \(\.$destinationPath)")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AutomationRuntime.requireService().exportContainer(
            id: container, to: URL(fileURLWithPath: destinationPath))
        return .result(dialog: "Exported \(container).")
    }
}
