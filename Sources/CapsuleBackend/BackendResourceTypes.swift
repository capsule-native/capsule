//
//  BackendResourceTypes.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Additional port value types: the raw escape-hatch result, the raw-retaining `Parsed`
//  wrapper, and lightweight summaries for the remaining command families. As with
//  `ContainerSummary`/`ImageSummary`, the domain maps these into its own models so wire
//  shapes never reach the UI.

import Foundation

/// The unfiltered result of a low-level `runRaw` invocation. Unlike the typed commands,
/// the escape hatch never throws on a non-zero exit — the caller inspects the fields.
public struct RawCommandOutput: Sendable, Equatable, Codable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// A decoded value paired with the exact raw payload it came from.
///
/// `value` is `nil` when the payload no longer matches the expected schema; `raw` is
/// always present, so a UI can fall back to a raw inspector instead of crashing when the
/// CLI's output format drifts.
public struct Parsed<Value: Sendable>: Sendable {
    public var value: Value?
    public var raw: String

    public init(value: Value?, raw: String) {
        self.value = value
        self.raw = raw
    }
}

/// A backend's lightweight view of a volume.
public struct VolumeSummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String { name }
    public var name: String
    public var source: String?
    public var sizeBytes: Int64?
    public var options: [String: String]
    public var labels: [String: String]
    /// Raw ISO-8601 creation timestamp; the domain parses it into a `Date`.
    public var createdAt: String?

    public init(
        name: String,
        source: String? = nil,
        sizeBytes: Int64? = nil,
        options: [String: String] = [:],
        labels: [String: String] = [:],
        createdAt: String? = nil
    ) {
        self.name = name
        self.source = source
        self.sizeBytes = sizeBytes
        self.options = options
        self.labels = labels
        self.createdAt = createdAt
    }
}

/// A backend's lightweight view of a network.
public struct NetworkSummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var name: String
    public var mode: String?
    public var gateway: String?
    public var subnet: String?
    public var plugin: String?
    public var ipv6Subnet: String?
    public var labels: [String: String]
    /// Raw ISO-8601 creation timestamp; the domain parses it into a `Date`.
    public var createdAt: String?
    /// True for runtime-managed networks (labeled `…resource.role: builtin`, e.g. `default`)
    /// that must not be deleted.
    public var isBuiltin: Bool

    public init(
        id: String,
        name: String,
        mode: String? = nil,
        gateway: String? = nil,
        subnet: String? = nil,
        plugin: String? = nil,
        ipv6Subnet: String? = nil,
        labels: [String: String] = [:],
        createdAt: String? = nil,
        isBuiltin: Bool = false
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.gateway = gateway
        self.subnet = subnet
        self.plugin = plugin
        self.ipv6Subnet = ipv6Subnet
        self.labels = labels
        self.createdAt = createdAt
        self.isBuiltin = isBuiltin
    }
}

/// A backend's view of a registry login.
public struct RegistrySummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String { server }
    public var server: String

    public init(server: String) {
        self.server = server
    }
}

/// A backend's lightweight view of a local DNS domain (`system dns list`).
public struct DNSDomainSummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String { domain }
    public var domain: String
    public var localhostIP: String?

    public init(domain: String, localhostIP: String? = nil) {
        self.domain = domain
        self.localhostIP = localhostIP
    }
}

/// A backend's lightweight view of a container machine (`machine list`).
public struct MachineSummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String { name }
    public var name: String
    public var state: String?
    /// Raw creation timestamp (ISO-8601 or CLI display string); the domain parses it.
    public var createdAt: String?
    public var ipAddress: String?
    public var cpus: Int?
    public var memory: String?
    public var disk: String?
    public var isDefault: Bool
    // Inspect-only detail (absent from `list`); surfaced read-only when present.
    public var kernel: String?
    public var nestedVirtualization: Bool?
    public var homeMount: String?

    public init(
        name: String, state: String? = nil, createdAt: String? = nil, ipAddress: String? = nil,
        cpus: Int? = nil, memory: String? = nil, disk: String? = nil, isDefault: Bool = false,
        kernel: String? = nil, nestedVirtualization: Bool? = nil, homeMount: String? = nil
    ) {
        self.name = name
        self.state = state
        self.createdAt = createdAt
        self.ipAddress = ipAddress
        self.cpus = cpus
        self.memory = memory
        self.disk = disk
        self.isDefault = isDefault
        self.kernel = kernel
        self.nestedVirtualization = nestedVirtualization
        self.homeMount = homeMount
    }
}

/// The status of the image builder instance.
public struct BuilderStatus: Sendable, Equatable, Codable {
    public var isRunning: Bool

    public init(isRunning: Bool) {
        self.isRunning = isRunning
    }
}

/// A backend's view of disk usage for one resource category (`system df`).
/// `total`/`active` are item COUNTS; `sizeInBytes`/`reclaimable` are BYTES.
public struct CategoryUsage: Sendable, Equatable, Codable {
    public var total: Int
    public var active: Int
    public var sizeInBytes: Int
    public var reclaimable: Int
    public var inUseBytes: Int { max(0, sizeInBytes - reclaimable) }

    public init(total: Int, active: Int, sizeInBytes: Int, reclaimable: Int) {
        self.total = total
        self.active = active
        self.sizeInBytes = sizeInBytes
        self.reclaimable = reclaimable
    }
}

/// One component of `container system version` (CLI client, API server, …).
public struct ComponentVersion: Sendable, Equatable, Identifiable, Codable {
    public var id: String { appName }
    public var appName: String
    public var version: String
    public var buildType: String
    public var commit: String

    public init(appName: String, version: String, buildType: String, commit: String) {
        self.appName = appName
        self.version = version
        self.buildType = buildType
        self.commit = commit
    }
}

/// Disk usage across images, containers, and volumes (`container system df`).
public struct StorageUsage: Sendable, Equatable, Codable {
    public var images: CategoryUsage
    public var containers: CategoryUsage
    public var volumes: CategoryUsage

    public init(images: CategoryUsage, containers: CategoryUsage, volumes: CategoryUsage) {
        self.images = images
        self.containers = containers
        self.volumes = volumes
    }
}

/// One key/value within a property section, rendered to a display string.
public struct PropertyEntry: Sendable, Equatable, Codable {
    public var key: String
    public var value: String
    public init(key: String, value: String) { self.key = key; self.value = value }
}

/// A `[section]` of merged system properties.
public struct PropertySection: Sendable, Equatable, Identifiable, Codable {
    public var id: String { name }
    public var name: String
    public var entries: [PropertyEntry]
    public init(name: String, entries: [PropertyEntry]) { self.name = name; self.entries = entries }
}

/// Merged system properties (`container system property list`), read-only.
public struct SystemProperties: Sendable, Equatable, Codable {
    public var sections: [PropertySection]
    public init(sections: [PropertySection]) { self.sections = sections }
    public func section(_ name: String) -> PropertySection? { sections.first { $0.name == name } }
}

/// Architecture for a kernel install.
public enum KernelArch: String, Sendable, Equatable, Codable, CaseIterable {
    case arm64, amd64
}

/// Where a kernel comes from. `recommended` downloads a known-good kernel and takes
/// precedence over all other flags (so its argv omits arch/binary/tar).
public enum KernelSource: Sendable, Equatable {
    case recommended
    case localBinary(path: String)
    case remoteTar(url: String, member: String?)
}

/// A typed `container system kernel set` invocation.
public struct KernelConfiguration: Sendable, Equatable {
    public var source: KernelSource
    public var arch: KernelArch
    public var force: Bool

    public init(source: KernelSource, arch: KernelArch = .arm64, force: Bool = false) {
        self.source = source
        self.arch = arch
        self.force = force
    }

    /// The argv after `container`: flags in source-dependent order.
    public var arguments: [String] {
        var argv = ["system", "kernel", "set"]
        switch source {
        case .recommended:
            argv.append("--recommended")
        case .localBinary(let path):
            argv += ["--arch", arch.rawValue, "--binary", path]
        case .remoteTar(let url, let member):
            argv += ["--arch", arch.rawValue, "--tar", url]
            if let member, !member.isEmpty { argv += ["--binary", member] }
        }
        if force { argv.append("--force") }
        return argv
    }
}
