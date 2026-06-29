//
//  MachineDraft.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// Draft model for machine creation in the wizard.
public struct MachineDraft: Sendable, Equatable {
    public var image: String = ""
    public var name: String = ""
    public var cpus: String = ""
    public var memory: String = ""
    public var homeMount: String = "rw"
    public var setDefault: Bool = false
    public var noBoot: Bool = false
    public var arch: String = ""
    public var os: String = ""
    public var platform: String = ""

    public init() {}
}

/// Draft model for machine settings updates.
public struct MachineSettingsDraft: Sendable, Equatable {
    public var cpus: String = ""
    public var memory: String = ""
    public var homeMount: String = "rw"

    public init() {}

    /// Seed from an existing machine's current values.
    public init(machine: Machine) {
        self.cpus = machine.cpus.map(String.init) ?? ""
        self.memory = machine.memory ?? ""
        self.homeMount = machine.homeMount ?? "rw"
    }
}
