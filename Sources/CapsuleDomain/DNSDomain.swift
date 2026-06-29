//
//  DNSDomain.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The domain's view
//  of a configured local DNS domain and the editable draft behind the Add Domain sheet.

import CapsuleBackend
import Foundation

/// A configured local DNS domain (apple/container's `system dns` resolves names under it).
public struct DNSDomain: Sendable, Equatable, Identifiable {
    public var domain: String
    public var localhostIP: String?
    public var id: String { domain }

    public init(domain: String, localhostIP: String? = nil) {
        self.domain = domain
        self.localhostIP = localhostIP
    }

    public init(summary: DNSDomainSummary) {
        self.init(domain: summary.domain, localhostIP: summary.localhostIP)
    }
}

/// The editable form behind the Add Domain sheet: a domain name and an optional localhost IP.
public struct DNSDraft: Sendable, Equatable {
    public var domain: String
    public var localhostIP: String

    public init(domain: String = "", localhostIP: String = "") {
        self.domain = domain
        self.localhostIP = localhostIP
    }
}
