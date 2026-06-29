//
//  Network.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The domain's
//  model of a container network — decoupled from the backend wire format. Subnet/gateway
//  are surfaced as copyable IPAM detail; `connectedContainers` is derived from the
//  attachment cross-reference; `isBuiltin` marks the runtime's protected networks.

import CapsuleBackend
import Foundation

/// The domain's model of a container network.
public struct Network: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var mode: String?
    public var plugin: String?
    public var ipv4Subnet: String?
    public var ipv4Gateway: String?
    public var ipv6Subnet: String?
    public var `internal`: Bool
    public var labels: [String: String]
    public var createdAt: Date?
    /// Containers attached to this network, derived from `container list -a`'s
    /// `configuration.networks[].network`. Empty until stamped by the browser model.
    public var connectedContainers: [String]
    /// A runtime-owned network (labelled `com.apple.container.resource.role: builtin`, e.g.
    /// `default`). Protected: cannot be deleted, excluded from prune/bulk.
    public var isBuiltin: Bool

    public init(
        id: String, name: String, mode: String? = nil, plugin: String? = nil,
        ipv4Subnet: String? = nil, ipv4Gateway: String? = nil, ipv6Subnet: String? = nil,
        internal: Bool = false, labels: [String: String] = [:], createdAt: Date? = nil,
        connectedContainers: [String] = [], isBuiltin: Bool = false
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.plugin = plugin
        self.ipv4Subnet = ipv4Subnet
        self.ipv4Gateway = ipv4Gateway
        self.ipv6Subnet = ipv6Subnet
        self.`internal` = `internal`
        self.labels = labels
        self.createdAt = createdAt
        self.connectedContainers = connectedContainers
        self.isBuiltin = isBuiltin
    }
}

extension Network {
    /// Maps a backend summary into the domain model, parsing the creation date and carrying
    /// the derived attachment stamp. `internal` is not exposed by `network list`, so it
    /// defaults to false (it is only ever set when creating a network).
    public init(summary: NetworkSummary, connectedContainers: [String] = []) {
        self.init(
            id: summary.id,
            name: summary.name,
            mode: summary.mode,
            plugin: summary.plugin,
            ipv4Subnet: summary.subnet,
            ipv4Gateway: summary.gateway,
            ipv6Subnet: summary.ipv6Subnet,
            internal: false,
            labels: summary.labels,
            createdAt: summary.createdAt.flatMap(Container.parseDate),
            connectedContainers: connectedContainers,
            isBuiltin: summary.isBuiltin)
    }
}
