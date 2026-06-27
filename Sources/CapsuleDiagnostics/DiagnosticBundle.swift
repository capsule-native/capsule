//
//  DiagnosticBundle.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import Foundation

/// Errors raised while producing a diagnostic bundle.
public enum DiagnosticsError: Error, Sendable, Equatable {
    case notImplemented
}

/// Collects logs and environment information into an exportable bundle for support.
///
/// Milestone 1 ships the shape only; `write(to:)` is implemented in a later milestone.
public struct DiagnosticBundle: Sendable {
    public var note: String

    public init(note: String = "Capsule diagnostic bundle (placeholder)") {
        self.note = note
    }

    /// Writes the bundle into `directory` and returns the created file URL.
    public func write(to directory: URL) throws -> URL {
        _ = directory
        throw DiagnosticsError.notImplemented
    }
}
