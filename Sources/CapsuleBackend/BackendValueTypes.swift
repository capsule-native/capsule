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

    public init(id: String, name: String, image: String, state: String) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
    }
}

/// A backend's lightweight view of an image.
public struct ImageSummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var reference: String
    public var sizeBytes: Int64

    public init(id: String, reference: String, sizeBytes: Int64) {
        self.id = id
        self.reference = reference
        self.sizeBytes = sizeBytes
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
