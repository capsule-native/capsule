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

/// A best-effort cross-reference from volumes/networks to the containers using them, built
/// from the most recent `container list -a`. Pure: the browser models build it and stamp
/// `attachedContainers`/`connectedContainers`, and the confirmation builders read it.
public struct AttachmentIndex: Sendable, Equatable {
    /// `volumeName -> [containerName]`.
    public let volumes: [String: [String]]
    /// `networkName -> [containerName]`.
    public let networks: [String: [String]]

    public init(volumes: [String: [String]], networks: [String: [String]]) {
        self.volumes = volumes
        self.networks = networks
    }

    /// The containers mounting `name`, or `[]` when none.
    public func containers(forVolume name: String) -> [String] {
        volumes[name] ?? []
    }

    /// The containers connected to `name`, or `[]` when none.
    public func containers(forNetwork name: String) -> [String] {
        networks[name] ?? []
    }

    /// Folds the per-container attachment slices into the two name→containers maps,
    /// preserving the input container order within each bucket.
    public static func build(from containers: [ContainerAttachmentInfo]) -> AttachmentIndex {
        var volumes: [String: [String]] = [:]
        var networks: [String: [String]] = [:]
        for container in containers {
            for source in container.volumeSources {
                volumes[source, default: []].append(container.containerName)
            }
            for network in container.networkNames {
                networks[network, default: []].append(container.containerName)
            }
        }
        return AttachmentIndex(volumes: volumes, networks: networks)
    }
}
