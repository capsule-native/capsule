//
//  BackendCapabilities.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Version-aware capability probing. The app calls `version()` once at startup and
//  derives the set of features the running build actually supports, so the UI can hide
//  or disable commands that a given CLI/server cannot serve (e.g. everything runtime
//  while the system service is stopped).

import Foundation

/// A command family the backend may or may not support for a given build/state.
public enum BackendFeature: String, Sendable, CaseIterable, Codable {
    case system
    case containers
    case images
    case volumes
    case networks
    case registries
    case machines
    case builder
    case logsFollow
}

/// The probed capabilities of a backend: the discovered versions plus the feature flags
/// derived from them.
public struct BackendCapabilities: Sendable, Equatable {
    public let clientVersion: String
    public let serverVersion: String?
    public let features: Set<BackendFeature>

    public init(clientVersion: String, serverVersion: String?, features: Set<BackendFeature>) {
        self.clientVersion = clientVersion
        self.serverVersion = serverVersion
        self.features = features
    }

    /// Whether a given command family is available in this build/state.
    public func supports(_ feature: BackendFeature) -> Bool {
        features.contains(feature)
    }

    /// Whether the background system service is up (a server version was reported).
    public var isSystemRunning: Bool { serverVersion != nil }

    /// Minimum CLI version Capsule requires before it will drive any command.
    public static let minimumSupportedClient = SemanticVersion(1, 0, 0)

    /// Runtime command families that additionally require the system service to be up.
    private static let runtimeFeatures: Set<BackendFeature> = [
        .containers, .images, .volumes, .networks, .registries, .machines, .builder,
        .logsFollow,
    ]

    /// Derives capabilities from a discovered version. Returns no features for a client
    /// below ``minimumSupportedClient``; otherwise `system` is always available and the
    /// runtime families are added only when a server version is present.
    public static func derive(from version: BackendVersion) -> BackendCapabilities {
        var features: Set<BackendFeature> = []
        if let client = SemanticVersion(parsing: version.client),
            client >= minimumSupportedClient
        {
            features.insert(.system)
            if version.server != nil {
                features.formUnion(runtimeFeatures)
            }
        }
        return BackendCapabilities(
            clientVersion: version.client,
            serverVersion: version.server,
            features: features
        )
    }
}
