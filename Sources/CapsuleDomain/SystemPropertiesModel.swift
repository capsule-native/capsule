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
        } catch {
            loadError = normalize(error).detail.explanation
        }
    }

    public var issues: [TOMLIssue] { PropertyTOML.lint(editBuffer) }
    public var changeReview: [String] { PropertyTOML.changes(from: originalTOML, to: editBuffer) }
    public var isDirty: Bool { editBuffer != originalTOML }
    public var exportText: String { editBuffer }

    /// Called on every buffer keystroke; does not set restartRequired (see markExported).
    public func markEdited() {}

    /// Called after a successful export write; signals that services need a restart to pick
    /// up the exported file. This is intentionally separate from markEdited() — the banner
    /// must not appear for in-flight edits that were never written to disk.
    public func markExported() { restartRequired = true }

    public func resetEdits() {
        editBuffer = originalTOML
        restartRequired = false
    }
}
