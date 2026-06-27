//
//  Image.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import Foundation

/// The domain's model of a container image, decoupled from the backend wire format so
/// that backend value types never leak into the UI.
public struct Image: Sendable, Equatable, Identifiable {
    public var id: String
    public var reference: String
    public var sizeBytes: Int64

    public init(id: String, reference: String, sizeBytes: Int64) {
        self.id = id
        self.reference = reference
        self.sizeBytes = sizeBytes
    }
}

extension Image {
    /// Maps a backend summary into the domain model.
    public init(summary: ImageSummary) {
        self.init(id: summary.id, reference: summary.reference, sizeBytes: summary.sizeBytes)
    }
}
