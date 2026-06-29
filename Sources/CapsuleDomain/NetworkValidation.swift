//
//  NetworkValidation.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The pure subnet-
//  conflict check behind the Create Network sheet's live validation. We detect and report
//  overlaps (naming the conflicting network) but never auto-pick a free subnet. The UI never
//  calls this directly — NetworkActionsModel surfaces it via subnetConflictMessage.

import Foundation

public enum NetworkValidation {
    /// Returns `nil` when `subnet` is empty (the runtime auto-assigns) or conflict-free.
    /// A malformed CIDR yields a syntax hint with an example; an overlap yields a message
    /// naming the conflicting network and both subnets so the user can resolve it.
    public static func subnetConflict(
        subnet: String, against existingNetworks: [Network]
    ) -> String? {
        let trimmed = subnet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard CIDR.parse(trimmed) != nil else {
            return "\"\(trimmed)\" isn't a valid CIDR subnet (for example, 10.0.0.0/24)."
        }
        for network in existingNetworks {
            for existing in [network.ipv4Subnet, network.ipv6Subnet].compactMap({ $0 }) {
                if CIDR.overlaps(trimmed, existing) {
                    return "Subnet \(trimmed) overlaps with network \"\(network.name)\" "
                        + "(\(existing))."
                }
            }
        }
        return nil
    }
}
