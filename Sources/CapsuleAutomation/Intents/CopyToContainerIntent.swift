//
//  CopyToContainerIntent.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import AppIntents
import Foundation

/// Copies a host file into a running container.
public struct CopyToContainerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Copy File to Container"
    public static let description = IntentDescription(
        "Copies a host file into a running container.",
        categoryName: "Containers")

    @Parameter(title: "File", description: "Path to the host file to copy.")
    public var sourcePath: String

    @Parameter(title: "Container", description: "The target container id or name.")
    public var container: String

    @Parameter(title: "Destination Path", description: "Absolute path inside the container.")
    public var containerPath: String

    public init() {}

    public init(sourcePath: String, container: String, containerPath: String) {
        self.sourcePath = sourcePath
        self.container = container
        self.containerPath = containerPath
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Copy \(\.$sourcePath) to \(\.$container)")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AutomationRuntime.requireService().copyToContainer(
            source: URL(fileURLWithPath: sourcePath),
            containerID: container,
            containerPath: containerPath)
        return .result(dialog: "Copied to \(container):\(containerPath).")
    }
}
