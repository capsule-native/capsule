//
//  VolumeDraft.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. UI-friendly drafts
//  the create sheets bind to. The model's `validatedConfiguration(_:)` turns a draft into a
//  `VolumeConfiguration` (the argv single-source-of-truth in CapsuleBackend).

import Foundation

/// A reusable advanced-options row (`key`/`value`) rendered as a `k=v` token. Shared by the
/// volume and network create sheets.
public struct KeyValueRow: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var key: String
    public var value: String

    public init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }

    /// The `key=value` token, or nil when the key is blank (a blank row is ignored).
    public var token: String? {
        key.isEmpty ? nil : "\(key)=\(value)"
    }
}

/// A UI-friendly draft of a volume to create.
public struct VolumeDraft: Sendable, Equatable {
    public var name: String
    /// Raw size, e.g. "10G". Validated against `isValidSize` before launch.
    public var size: String
    /// Driver `--opt` rows.
    public var options: [KeyValueRow]
    /// `--label` rows.
    public var labels: [KeyValueRow]

    public init(
        name: String = "", size: String = "",
        options: [KeyValueRow] = [], labels: [KeyValueRow] = []
    ) {
        self.name = name
        self.size = size
        self.options = options
        self.labels = labels
    }

    /// A size is valid only as a number (optionally fractional) followed by a single
    /// K/M/G/T/P suffix (case-insensitive) — the suffixes the CLI's `-s` accepts.
    public static func isValidSize(_ raw: String) -> Bool {
        guard let last = raw.last, "kKmMgGtTpP".contains(last) else { return false }
        let number = raw.dropLast()
        guard !number.isEmpty else { return false }
        return Double(number) != nil
    }
}
