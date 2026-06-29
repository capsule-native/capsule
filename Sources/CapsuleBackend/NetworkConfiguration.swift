//
//  NetworkConfiguration.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  A typed description of a `container network create` invocation. Its `arguments` is the
//  single source of truth for the argv (after the `container` executable), shared by the
//  CLI adapter and the domain's create sheet. Flags mirror `container network create`
//  v1.0.0 (verified against `--help`): the gateway is derived from the subnet (not set
//  directly); the default plugin is `container-network-vmnet`.

import Foundation

public struct NetworkConfiguration: Sendable, Equatable {
    public var name: String
    public var subnet: String?
    public var subnetV6: String?
    public var `internal`: Bool
    /// Driver options as `k=v` tokens, each emitted as `--option k=v`.
    public var options: [String]
    /// Labels as `k=v` tokens, each emitted as `--label k=v`.
    public var labels: [String]
    public var plugin: String?

    public init(
        name: String,
        subnet: String? = nil,
        subnetV6: String? = nil,
        internal: Bool = false,
        options: [String] = [],
        labels: [String] = [],
        plugin: String? = nil
    ) {
        self.name = name
        self.subnet = subnet
        self.subnetV6 = subnetV6
        self.internal = `internal`
        self.options = options
        self.labels = labels
        self.plugin = plugin
    }

    /// The argv after `container`: --internal, labels, options, plugin, subnet,
    /// subnet-v6, then the positional name.
    public var arguments: [String] {
        var argv = ["network", "create"]
        if `internal` { argv.append("--internal") }
        for label in labels { argv += ["--label", label] }
        for opt in options { argv += ["--option", opt] }
        if let plugin { argv += ["--plugin", plugin] }
        if let subnet { argv += ["--subnet", subnet] }
        if let subnetV6 { argv += ["--subnet-v6", subnetV6] }
        argv.append(name)
        return argv
    }
}
