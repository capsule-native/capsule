//
//  SystemPropertiesModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  CapsuleDomain — free of UI / Foundation.Process dependencies.

import CapsuleBackend
import Foundation
import Observation

/// Owns the system-properties story: loads the TOML + structured sections from the backend,
/// maintains an editable buffer, surfaces lint issues and a change review, and tracks
/// whether a restart is needed when the buffer diverges from the original.
@MainActor
@Observable
public final class SystemPropertiesModel {
    public private(set) var sections: [PropertySection] = []
    public private(set) var originalTOML = ""
    public var editBuffer = ""
    public private(set) var restartRequired = false
    public private(set) var loadError: String?

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError =
            SystemStatusModel.defaultNormalize
    ) {
        self.backend = backend
        self.normalize = normalize
    }

    public func load() async {
        do {
            let toml = try await backend.systemPropertiesTOML()
            let props = try await backend.systemProperties()
            originalTOML = toml
            editBuffer = toml
            sections = props.sections
            loadError = nil
            restartRequired = false  // new baseline from disk; daemon is in sync
        } catch {
            loadError = normalize(error).detail.explanation
        }
    }

    public var issues: [TOMLIssue] { PropertyTOML.lint(editBuffer) }
    public var changeReview: [String] { PropertyTOML.changes(from: originalTOML, to: editBuffer) }
    public var isDirty: Bool { editBuffer != originalTOML }
    public var exportText: String { editBuffer }

    /// Called after a successful export write; signals that services need a restart to pick
    /// up the exported file. The banner must not appear for in-flight edits that were never
    /// written to disk. restartRequired is cleared only by load() (new disk baseline) or
    /// when the daemon is confirmed restarted.
    public func markExported() { restartRequired = true }

    /// Reverts the edit buffer to the last loaded TOML. Does NOT clear restartRequired —
    /// if the file on disk was already written by a prior export, a restart is still needed
    /// regardless of what is in the buffer.
    public func resetEdits() {
        editBuffer = originalTOML
    }
}
