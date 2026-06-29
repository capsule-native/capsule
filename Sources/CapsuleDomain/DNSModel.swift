//
//  DNSModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Local DNS domain
//  management for the Networking preferences pane. Listing is unprivileged; create and delete
//  always require administrator rights, so they are NOT attempted in-process — they build the
//  argv and hand it to an injected privileged-Terminal closure (the App layer prefixes
//  `sudo`). The in-process safety net for an admin rejection on the list path is
//  `permissionRequired(.administrator)`, produced by the injected normalizer (the mapping is
//  owned by Phase 1's ErrorNormalizer; this model only consumes it).

import CapsuleBackend
import Foundation
import Observation

/// The load state of the DNS domain list, distinguishing a down service from no domains.
public enum DNSLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case unavailable(ErrorDetail)
}

@MainActor
@Observable
public final class DNSModel {
    public private(set) var domains: [DNSDomain] = []
    public private(set) var loadState: DNSLoadState = .idle
    public var notice: LifecycleNotice?

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void
    private let runPrivilegedInTerminal: @MainActor ([String]) -> Void

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in },
        runPrivilegedInTerminal: @escaping @MainActor ([String]) -> Void
    ) {
        self.backend = backend
        self.normalize = normalize
        self.onActivity = onActivity
        self.runPrivilegedInTerminal = runPrivilegedInTerminal
    }

    /// Lists the configured local DNS domains. This is the only unprivileged DNS operation.
    /// An empty result is `.loaded` with no domains ("No local DNS domains"); a thrown error
    /// is `.unavailable` so the pane never confuses a down service with an empty list.
    public func refresh() async {
        loadState = .loading
        do {
            let summaries = try await backend.listDNSDomains()
            domains = summaries.map(DNSDomain.init(summary:))
            loadState = .loaded
        } catch {
            domains = []
            loadState = .unavailable(normalize(error).detail)
        }
    }

    /// Validates the draft and, on success, hands the privileged `system dns create` argv to
    /// the injected Terminal closure (the App layer prefixes `sudo`). Returns the validation
    /// failure otherwise. Never attempts the create in-process — admin is always required.
    @discardableResult
    public func addDomain(_ draft: DNSDraft) -> Result<Void, CapsuleError> {
        switch validatedConfiguration(draft) {
        case let .failure(error):
            return .failure(error)
        case let .success(config):
            runPrivilegedInTerminal(config.arguments)
            onActivity(
                "Requested DNS domain \(config.domain) (requires administrator — opens Terminal).")
            return .success(())
        }
    }

    /// Hands the privileged `system dns delete` argv to the injected Terminal closure.
    public func deleteDomain(_ domain: String) {
        let config = DNSConfiguration(domain: domain)
        runPrivilegedInTerminal(config.deleteArguments)
        onActivity(
            "Requested removal of DNS domain \(domain) (requires administrator — opens Terminal).")
    }

    /// Validates a draft into a `DNSConfiguration`: a non-empty, syntactically valid domain
    /// name and an optional, well-formed IPv4 localhost address.
    func validatedConfiguration(_ draft: DNSDraft) -> Result<DNSConfiguration, CapsuleError> {
        let domain = draft.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty else {
            return .failure(.invalidInput(field: "domain", message: "Enter a domain name."))
        }
        guard Self.isValidDomain(domain) else {
            return .failure(
                .invalidInput(
                    field: "domain",
                    message: "\(domain) is not a valid domain name (e.g. test or app.test)."))
        }
        let ip = draft.localhostIP.trimmingCharacters(in: .whitespacesAndNewlines)
        if ip.isEmpty {
            return .success(DNSConfiguration(domain: domain))
        }
        guard Self.isValidIPv4(ip) else {
            return .failure(
                .invalidInput(
                    field: "localhostIP",
                    message: "\(ip) is not a valid IPv4 address (e.g. 127.0.0.1)."))
        }
        return .success(DNSConfiguration(domain: domain, localhostIP: ip))
    }

    private static func isValidDomain(_ text: String) -> Bool {
        let pattern =
            "^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isValidIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), String(value) == part, (0...255).contains(value) else {
                return false
            }
            return true
        }
    }
}
