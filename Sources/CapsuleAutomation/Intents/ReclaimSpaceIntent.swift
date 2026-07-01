//
//  ReclaimSpaceIntent.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import AppIntents

/// Reclaims disk space by pruning unused containers, images, and volumes.
public struct ReclaimSpaceIntent: AppIntent {
    public static let title: LocalizedStringResource = "Reclaim Space"
    public static let description = IntentDescription(
        "Prunes unused containers, images, and volumes to reclaim disk space.",
        categoryName: "System")

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog
    {
        let summary = try await AutomationRuntime.requireService().reclaimSpace()
        return .result(value: summary, dialog: "Reclaimed unused space.")
    }
}
