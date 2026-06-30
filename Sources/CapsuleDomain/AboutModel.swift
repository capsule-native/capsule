//
//  AboutModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The model is
//  `@Observable` (from `Observation`, not SwiftUI) so the UI can bind to it while the
//  domain stays UI-free.

import CapsuleBackend
import Foundation
import Observation

/// Owns the "About" story: component version listing, client/server compatibility check,
/// and a pre-formatted bug-report text block.
@MainActor
@Observable
public final class AboutModel {
    public private(set) var components: [ComponentVersion] = []
    public private(set) var loadFailed: String?

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let appVersion: String
    private let osVersion: String

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        appVersion: String,
        osVersion: String
    ) {
        self.backend = backend
        self.normalize = normalize
        self.appVersion = appVersion
        self.osVersion = osVersion
    }

    public func refresh() async {
        do { components = try await backend.systemComponentVersions(); loadFailed = nil } catch {
            loadFailed = normalize(error).detail.explanation
        }
    }

    /// First numeric `major.minor.patch` found in a (possibly messy) version string.
    private func semver(_ s: String) -> SemanticVersion? {
        SemanticVersion(parsing: s)
    }

    public var compatibilityWarnings: [String] {
        guard
            let client = components.first(where: { $0.appName == "container" })?.version,
            let server = components.first(where: { $0.appName.contains("apiserver") })?.version,
            let cv = semver(client), let sv = semver(server)
        else { return [] }
        if cv.major != sv.major || cv.minor != sv.minor {
            return [
                "CLI (\(client)) and API server differ in version — update both to matching releases."
            ]
        }
        return []
    }

    public var bugReportText: String {
        var lines = ["Capsule \(appVersion)", osVersion, ""]
        lines += components.map { "\($0.appName): \($0.version) (\($0.buildType), \($0.commit))" }
        if !compatibilityWarnings.isEmpty { lines += [""] + compatibilityWarnings }
        return lines.joined(separator: "\n")
    }
}
