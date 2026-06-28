//
//  SidebarSection.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import Foundation

/// The navigable sections in the resource sidebar.
///
/// Resource sections map to a ``SystemFeature`` and are disabled when that family is
/// unavailable (e.g. the service is stopped); ``system`` is always available so the user
/// can reach status, version, and Start/Stop even when nothing else is.
public enum SidebarSection: String, CaseIterable, Identifiable, Sendable {
    case containers
    case images
    case volumes
    case networks
    case machines
    case system

    public var id: String { rawValue }

    /// The user-facing label.
    public var title: String {
        switch self {
        case .containers: return "Containers"
        case .images: return "Images"
        case .volumes: return "Volumes"
        case .networks: return "Networks"
        case .machines: return "Machines"
        case .system: return "System"
        }
    }

    /// The SF Symbol shown beside the label.
    public var symbolName: String {
        switch self {
        case .containers: return "shippingbox"
        case .images: return "square.stack.3d.up"
        case .volumes: return "externaldrive"
        case .networks: return "network"
        case .machines: return "cpu"
        case .system: return "gauge.with.dots.needle.bottom.50percent"
        }
    }

    /// The feature this section needs to be usable, or `nil` when it is always available.
    public var requiredFeature: SystemFeature? {
        switch self {
        case .containers: return .containers
        case .images: return .images
        case .volumes: return .volumes
        case .networks: return .networks
        case .machines: return .machines
        case .system: return nil
        }
    }

    /// Whether the section can be opened given the currently available features.
    public func isEnabled(features: Set<SystemFeature>) -> Bool {
        guard let required = requiredFeature else { return true }
        return features.contains(required)
    }
}
