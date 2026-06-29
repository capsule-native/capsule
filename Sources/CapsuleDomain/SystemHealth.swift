//
//  SystemHealth.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. These are
//  UI-facing value types: the domain maps the backend's `BackendVersion` /
//  `BackendCapabilities` into these mirrors so `CapsuleUI` (which imports only the domain)
//  can render system health without ever seeing a backend type.

import CapsuleBackend
import Foundation

/// A UI-facing mirror of the backend's reported version pair.
public struct SystemVersion: Sendable, Equatable {
    public var client: String
    public var server: String?

    public init(client: String, server: String? = nil) {
        self.client = client
        self.server = server
    }
}

/// A UI-facing mirror of `BackendFeature` — same raw values, so capabilities map across
/// the boundary by name without the UI importing `CapsuleBackend`.
public enum SystemFeature: String, Sendable, CaseIterable, Codable {
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

/// How a system-health banner should be tinted.
public enum BannerKind: Sendable, Equatable {
    case healthy
    case caution
    case unhealthy
    case info
}

/// The whole system-health story the UI binds to.
///
/// Crucially this distinguishes ``stopped`` (a reachable, cleanly-stopped service) and
/// ``unavailable`` (an unreachable / errored service) from a *running* one — so the UI
/// can render an explicit unhealthy state rather than mistaking "no data" for "healthy".
public enum SystemHealth: Sendable, Equatable {
    /// Not yet probed.
    case unknown
    /// A probe is in flight.
    case checking
    /// The service is up; carries the version pair and the available feature families.
    case running(version: SystemVersion, features: Set<SystemFeature>)
    /// The service is reachable but stopped.
    case stopped
    /// The service is unreachable or errored; carries a presentation-ready detail.
    case unavailable(ErrorDetail)

    /// Whether runtime commands can be issued (the service is up).
    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    /// The feature families currently available (empty unless running).
    public var availableFeatures: Set<SystemFeature> {
        if case let .running(_, features) = self { return features }
        return []
    }

    /// Whether `feature` is usable right now — the service is running *and* the build
    /// reports the family. Resource surfaces and their Create / Delete / Clean-Up controls
    /// gate on this so an OS or container build that lacks a family disables (rather than
    /// errors on) that UI. Mirrors ``SidebarSection/isEnabled(features:)`` but folds in the
    /// running check, since controls only ever render inside a running service.
    public func supports(_ feature: SystemFeature) -> Bool {
        isRunning && availableFeatures.contains(feature)
    }

    /// How the banner should be tinted for this state.
    public var bannerKind: BannerKind {
        switch self {
        case .running: return .healthy
        case .stopped, .unavailable: return .unhealthy
        case .unknown, .checking: return .info
        }
    }

    /// A one-word status label for compact indicators (the sidebar footer, the System
    /// pane).
    public var statusLabel: String {
        switch self {
        case .unknown, .checking: return "Checking…"
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .unavailable: return "Unavailable"
        }
    }
}

/// Returns a human-readable compatibility warning when the discovered client/server
/// versions fall outside what Capsule expects, or `nil` when everything is compatible.
///
/// - A client below ``BackendCapabilities/minimumSupportedClient`` is unsupported.
/// - A running server whose major version differs from the client's is a mismatch.
public func compatibilityWarning(forClient client: String, server: String?) -> String? {
    let minimum = BackendCapabilities.minimumSupportedClient
    guard let clientVersion = SemanticVersion(parsing: client) else {
        return "Capsule could not determine the container CLI version (\(client))."
    }
    if clientVersion < minimum {
        return
            "Capsule requires container CLI \(minimum.major).\(minimum.minor).\(minimum.patch) "
            + "or newer, but found \(client)."
    }
    if let server, let serverVersion = SemanticVersion(parsing: server),
        serverVersion.major != clientVersion.major
    {
        return "The container CLI (\(client)) and service (\(server)) major versions differ."
    }
    return nil
}
