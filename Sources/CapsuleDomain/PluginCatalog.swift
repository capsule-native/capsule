//
//  PluginCatalog.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Plugin discovery is
//  modeled behind a pure `PluginDiscovering` seam so the domain stays decoupled from the
//  filesystem; the concrete `LibexecPluginScanner` lives in the composition root (CapsuleApp).

/// A `container` plugin resolved from a libexec directory: an external `container-<name>`
/// binary invoked as the subcommand `container <name>`.
public struct PluginInfo: Identifiable, Equatable, Sendable {
    /// The subcommand name (the part after the `container-` prefix).
    public var name: String
    /// The absolute path of the backing `container-<name>` executable.
    public var path: String
    public var id: String { name }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

/// The seam for enumerating installed `container` plugins. Pure data out; the concrete
/// scanner (a filesystem walk) is injected by the composition root so the domain is testable
/// with a fake.
public protocol PluginDiscovering: Sendable {
    func installedPlugins() -> [PluginInfo]
}

/// The inert default used by previews/tests with no real scanner wired.
public struct NoPluginDiscovery: PluginDiscovering {
    public init() {}
    public func installedPlugins() -> [PluginInfo] { [] }
}
