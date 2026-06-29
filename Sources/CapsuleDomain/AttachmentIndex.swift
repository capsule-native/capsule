//
//  AttachmentIndex.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The attachment
//  index is pure data derived from `container list -a`, so it is fully unit-testable.

import Foundation

/// The attachment-relevant slice of a container, extracted from
/// `container list -a --format json` (`configuration.mounts[].type.volume.name` and
/// `configuration.networks[].network`). This is the sole input to `AttachmentIndex`.
public struct ContainerAttachmentInfo: Sendable, Equatable {
    public var containerName: String
    public var volumeSources: [String]
    public var networkNames: [String]

    public init(containerName: String, volumeSources: [String], networkNames: [String]) {
        self.containerName = containerName
        self.volumeSources = volumeSources
        self.networkNames = networkNames
    }

    /// Maps a domain `Container` (carrying `volumeMounts`/`networkNames`) into the index input.
    public init(container: Container) {
        self.init(
            containerName: container.name,
            volumeSources: container.volumeMounts,
            networkNames: container.networkNames
        )
    }
}
