//
//  Resource.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Process
//  execution lives exclusively in `CapsuleCLIBackend`.

import CapsuleBackend
import Foundation

/// The kinds of resource Capsule manages.
public enum ResourceKind: String, Sendable, CaseIterable, Codable, Identifiable {
    case container
    case image
    case volume
    case network

    public var id: String { rawValue }
}

/// The lifecycle state of a container, normalized from whatever string a backend reports.
public enum ContainerState: String, Sendable, Codable {
    case created
    case running
    case paused
    case stopped
    case unknown

    init(backendState: String) {
        switch backendState.lowercased() {
        case "created": self = .created
        case "running", "up": self = .running
        case "paused": self = .paused
        case "stopped", "exited", "dead": self = .stopped
        default: self = .unknown
        }
    }
}

/// The domain's model of a container — richer and UI-friendly, decoupled from the
/// backend wire format.
public struct Container: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var image: String
    public var state: ContainerState

    public init(id: String, name: String, image: String, state: ContainerState) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
    }
}

extension Container {
    /// Maps a backend summary into the domain model.
    public init(summary: ContainerSummary) {
        self.init(
            id: summary.id,
            name: summary.name,
            image: summary.image,
            state: ContainerState(backendState: summary.state)
        )
    }
}
