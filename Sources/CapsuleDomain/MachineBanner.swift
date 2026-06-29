//
//  MachineBanner.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// A success or informational banner displayed after a machine operation.
public struct MachineBanner: Sendable, Equatable, Identifiable {
    /// The kind of banner event.
    public enum Kind: Sendable, Equatable {
        case created(name: String)
        case stopped(name: String)
        case implicitBoot(name: String)
        case madeDefault(name: String, previous: String?)
    }

    public var kind: Kind
    public var id: String {
        switch kind {
        case .created(let name): "created-\(name)"
        case .stopped(let name): "stopped-\(name)"
        case .implicitBoot(let name): "implicit-boot-\(name)"
        case .madeDefault(let name, let previous): "made-default-\(name)-\(previous ?? "none")"
        }
    }

    public var title: String {
        switch kind {
        case .created: "Machine created"
        case .stopped: "Machine stopped"
        case .implicitBoot: "Booting machine"
        case .madeDefault: "Default machine updated"
        }
    }

    public var message: String {
        switch kind {
        case .created(let name): "Machine \(name) has been created."
        case .stopped(let name): "Machine \(name) has been stopped."
        case .implicitBoot(let name): "Capsule is booting \(name) …"
        case .madeDefault(let name, _): "\(name) is now the default machine."
        }
    }

    public init(kind: Kind) {
        self.kind = kind
    }
}
