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

/// A backend's lightweight view of a container machine.
public struct MachineSummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String { name }
    public var name: String
    public var state: String?

    public init(name: String, state: String? = nil) {
        self.name = name
        self.state = state
    }
}

/// The status of the image builder instance.
public struct BuilderStatus: Sendable, Equatable, Codable {
    public var isRunning: Bool

    public init(isRunning: Bool) {
        self.isRunning = isRunning
    }
}
