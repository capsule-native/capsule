//
//  NetworkDraft.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The editable draft
//  behind the Create Network sheet. `NetworkActionsModel.validatedConfiguration` turns it
//  into a backend `NetworkConfiguration` (the argv single-source-of-truth) after the
//  subnet-conflict check.

import Foundation

public struct NetworkDraft: Sendable, Equatable {
    public var name: String
    public var subnet: String
    public var subnetV6: String
    public var isInternal: Bool
    public var options: [KeyValueRow]
    public var labels: [KeyValueRow]
    public var plugin: String

    public init(
        name: String = "",
        subnet: String = "",
        subnetV6: String = "",
        isInternal: Bool = false,
        options: [KeyValueRow] = [],
        labels: [KeyValueRow] = [],
        plugin: String = ""
    ) {
        self.name = name
        self.subnet = subnet
        self.subnetV6 = subnetV6
        self.isInternal = isInternal
        self.options = options
        self.labels = labels
        self.plugin = plugin
    }
}
