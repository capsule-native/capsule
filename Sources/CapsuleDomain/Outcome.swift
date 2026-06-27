//
//  Outcome.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// A normalized, user-presentable description of something that went wrong.
///
/// Raw `Error` values are mapped into this type by `CapsuleDiagnostics` so the UI
/// only ever renders stable, friendly diagnostics.
public struct DiagnosticInfo: Sendable, Equatable, Codable {
    /// A short, human-readable summary (one line).
    public var summary: String
    /// Optional additional detail shown on request.
    public var detail: String?
    /// A developer-facing description of the underlying error, for diagnostic bundles.
    public var underlyingDescription: String?

    public init(summary: String, detail: String? = nil, underlyingDescription: String? = nil) {
        self.summary = summary
        self.detail = detail
        self.underlyingDescription = underlyingDescription
    }
}

/// The result of an operation that can fail with a normalized diagnostic.
public enum Outcome<Success: Sendable>: Sendable {
    case success(Success)
    case failure(DiagnosticInfo)

    public var diagnostic: DiagnosticInfo? {
        if case let .failure(info) = self { return info }
        return nil
    }
}
