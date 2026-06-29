//
//  VolumeConfiguration.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  A typed description of a `container volume create` invocation. Its `arguments` is the
//  single source of truth for the argv (after the `container` executable), shared by the
//  CLI adapter and the domain's create sheet. Flags mirror `container volume create`
//  v1.0.0 (verified against `--help`): no --driver / --source / --name flags exist;
//  `-s <size>` accepts a K/M/G/T/P suffix.

import Foundation

public struct VolumeConfiguration: Sendable, Equatable {
    public var name: String
    /// Size string rendered as `-s <value>` (pre-validated K/M/G/T/P suffix).
    public var size: String?
    /// Driver options as `k=v` tokens, each emitted as `--opt k=v`.
    public var options: [String]
    /// Labels as `k=v` tokens, each emitted as `--label k=v`.
    public var labels: [String]

    public init(
        name: String,
        size: String? = nil,
        options: [String] = [],
        labels: [String] = []
    ) {
        self.name = name
        self.size = size
        self.options = options
        self.labels = labels
    }

    /// The argv after `container`: labels, then opts, then size, then the positional name.
    public var arguments: [String] {
        var argv = ["volume", "create"]
        for label in labels { argv += ["--label", label] }
        for opt in options { argv += ["--opt", opt] }
        if let size { argv += ["-s", size] }
        argv.append(name)
        return argv
    }
}
