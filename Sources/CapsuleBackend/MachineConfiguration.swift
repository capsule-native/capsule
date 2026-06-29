//
//  MachineConfiguration.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Typed argv builder for `container machine create`. Single source of truth for create
//  arguments. `image` is the trailing positional; nested-virtualization and kernel are not
//  modelled because the CLI (v1.0.0) cannot set them.

import Foundation

public struct MachineConfiguration: Sendable, Equatable {
    public var image: String
    public var name: String?
    public var cpus: Int?
    public var memory: String?
    public var homeMount: String?
    public var arch: String?
    public var os: String?
    public var platform: String?
    public var setDefault: Bool
    public var noBoot: Bool

    public init(
        image: String, name: String? = nil, cpus: Int? = nil, memory: String? = nil,
        homeMount: String? = nil, arch: String? = nil, os: String? = nil, platform: String? = nil,
        setDefault: Bool = false, noBoot: Bool = false
    ) {
        self.image = image
        self.name = name
        self.cpus = cpus
        self.memory = memory
        self.homeMount = homeMount
        self.arch = arch
        self.os = os
        self.platform = platform
        self.setDefault = setDefault
        self.noBoot = noBoot
    }

    /// The argv after `container`: flags in order, then image as trailing positional.
    public var arguments: [String] {
        var argv = ["machine", "create"]
        if let name { argv += ["--name", name] }
        if let cpus { argv += ["--cpus", String(cpus)] }
        if let memory { argv += ["--memory", memory] }
        if let homeMount { argv += ["--home-mount", homeMount] }
        if let arch { argv += ["--arch", arch] }
        if let os { argv += ["--os", os] }
        if let platform { argv += ["--platform", platform] }
        if setDefault { argv.append("--set-default") }
        if noBoot { argv.append("--no-boot") }
        argv.append(image)
        return argv
    }
}
