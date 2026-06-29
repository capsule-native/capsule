//
//  Volume.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The domain's
//  model of a storage volume — decoupled from the backend wire format, with the attachment
//  cross-reference (`attachedContainers`) stamped by `VolumeBrowserModel` from the
//  AttachmentIndex.

import CapsuleBackend
import Foundation

/// The domain's model of a storage volume.
public struct Volume: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var source: String?
    public var sizeBytes: Int64?
    public var options: [String: String]
    public var labels: [String: String]
    public var createdAt: Date?
    /// Containers that mount this volume, derived from the AttachmentIndex (best-effort,
    /// as fresh as the last container list). Empty when nothing mounts it.
    public var attachedContainers: [String]

    public init(
        name: String,
        source: String? = nil,
        sizeBytes: Int64? = nil,
        options: [String: String] = [:],
        labels: [String: String] = [:],
        createdAt: Date? = nil,
        attachedContainers: [String] = []
    ) {
        self.name = name
        self.source = source
        self.sizeBytes = sizeBytes
        self.options = options
        self.labels = labels
        self.createdAt = createdAt
        self.attachedContainers = attachedContainers
    }
}

extension Volume {
    /// Maps a backend summary into the domain model, parsing the ISO-8601 creation date and
    /// stamping any cross-referenced attachments.
    public init(summary: VolumeSummary, attachedContainers: [String] = []) {
        self.init(
            name: summary.name,
            source: summary.source,
            sizeBytes: summary.sizeBytes,
            options: summary.options,
            labels: summary.labels,
            createdAt: summary.createdAt.flatMap(Container.parseDate),
            attachedContainers: attachedContainers)
    }
}
