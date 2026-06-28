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
    case stopping
    case stopped
    case unknown

    init(backendState: String) {
        switch backendState.lowercased() {
        case "created": self = .created
        case "running", "up": self = .running
        case "paused": self = .paused
        case "stopping": self = .stopping
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
    public var ip: String?
    public var createdAt: Date?

    public init(
        id: String, name: String, image: String, state: ContainerState,
        ip: String? = nil, createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.ip = ip
        self.createdAt = createdAt
    }

    /// The leading 12 characters of the id, for compact display.
    public var shortID: String { String(id.prefix(12)) }
}

extension Container {
    /// Maps a backend summary into the domain model, parsing the ISO-8601 creation date.
    public init(summary: ContainerSummary) {
        self.init(
            id: summary.id,
            name: summary.name,
            image: summary.image,
            state: ContainerState(backendState: summary.state),
            ip: summary.ip,
            createdAt: summary.createdAt.flatMap(Container.parseDate)
        )
    }

    /// Parses an ISO-8601 timestamp, tolerating the presence or absence of fractional
    /// seconds, and returning `nil` for anything unrecognizable.
    static func parseDate(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
