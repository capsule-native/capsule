//
//  DNSConfiguration.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  A typed description of the privileged `container system dns create/delete` invocations.
//  `system dns create`/`delete` MUST run as an administrator, so this argv is consumed by
//  the domain DNS model and executed via the App-layer sudo Terminal handoff — it is
//  NEVER run through the CLI adapter. Flags mirror `container system dns` v1.0.0.

import Foundation

public struct DNSConfiguration: Sendable, Equatable {
    public var domain: String
    public var localhostIP: String?

    public init(domain: String, localhostIP: String? = nil) {
        self.domain = domain
        self.localhostIP = localhostIP
    }

    /// Privileged create argv — consumed by the DNS model + the sudo Terminal handoff.
    public var arguments: [String] {
        var argv = ["system", "dns", "create"]
        if let localhostIP { argv += ["--localhost", localhostIP] }
        argv.append(domain)
        return argv
    }

    /// Privileged delete argv companion.
    public var deleteArguments: [String] { ["system", "dns", "delete", domain] }
}
