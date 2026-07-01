//
//  ContainerLogsIntent.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The automatable form of "follow logs": a one-shot snapshot of a container's recent output
//  (a live-following stream doesn't fit a single Shortcuts step). Returns the text so it can
//  feed a following action.
//

import AppIntents

/// Fetches a snapshot of a container's logs.
public struct ContainerLogsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Container Logs"
    public static let description = IntentDescription(
        "Returns a snapshot of a container's recent logs.",
        categoryName: "Containers")

    @Parameter(title: "Container", description: "The container id or name.")
    public var container: String

    @Parameter(title: "Line Limit", description: "Maximum number of recent lines to return.")
    public var tail: Int?

    public init() {}

    public init(container: String, tail: Int? = nil) {
        self.container = container
        self.tail = tail
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Get logs for \(\.$container)")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog
    {
        let logs = try await AutomationRuntime.requireService().containerLogs(
            id: container, tail: tail)
        return .result(value: logs, dialog: "Fetched logs for \(container).")
    }
}
