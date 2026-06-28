//
//  BackendValueTypes.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// Version information reported by a backend.
public struct BackendVersion: Sendable, Equatable, Codable {
    public var client: String
    public var server: String?

    public init(client: String, server: String? = nil) {
        self.client = client
        self.server = server
    }
}

/// A backend's lightweight view of a container. The domain maps this into its own,
/// richer `Container` model so that wire formats never leak into the UI.
public struct ContainerSummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var name: String
    public var image: String
    public var state: String
    /// The container's primary IPv4 address (without CIDR suffix), if attached.
    public var ip: String?
    /// The container's creation timestamp as the raw ISO-8601 string the CLI emits.
    public var createdAt: String?

    public init(
        id: String, name: String, image: String, state: String,
        ip: String? = nil, createdAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.ip = ip
        self.createdAt = createdAt
    }
}

/// A backend's lightweight view of an image. `digest` is the full content digest
/// (`sha256:…`) the UI uses for unambiguous, digest-centric copy actions; `createdAt` is
/// the raw ISO-8601 string the CLI emits (the domain parses it into a `Date`).
public struct ImageSummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var reference: String
    public var sizeBytes: Int64
    public var digest: String
    public var createdAt: String?

    public init(
        id: String, reference: String, sizeBytes: Int64,
        digest: String = "", createdAt: String? = nil
    ) {
        self.id = id
        self.reference = reference
        self.sizeBytes = sizeBytes
        self.digest = digest
        self.createdAt = createdAt
    }
}

/// Errors that any backend adapter may surface. Normalized for display by
/// `CapsuleDiagnostics`.
public enum BackendError: Error, Sendable, Equatable {
    /// The operation is recognized but not implemented yet (Milestone 1 stubs).
    case notImplemented(String)
    /// The backend executable could not be located.
    case executableNotFound(String)
    /// The backend process exited with a non-zero status.
    case nonZeroExit(command: String, code: Int32, stderr: String)
    /// The backend output could not be decoded into a value type.
    case decodingFailed(String)
}
