//
//  MachineImagePreset.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// A curated distro/OCI image option for the create wizard. The wizard also offers a custom
/// reference, so this list is convenience, not a constraint.
public struct MachineImagePreset: Sendable, Equatable, Identifiable {
    public var id: String { reference }
    public var displayName: String
    public var reference: String
    public init(displayName: String, reference: String) {
        self.displayName = displayName; self.reference = reference
    }
    public static let all: [MachineImagePreset] = [
        .init(displayName: "Alpine 3.22", reference: "alpine:3.22"),
        .init(displayName: "Ubuntu 24.04", reference: "ubuntu:24.04"),
        .init(displayName: "Debian 12", reference: "debian:12"),
        .init(displayName: "Fedora 40", reference: "fedora:40"),
    ]
}
