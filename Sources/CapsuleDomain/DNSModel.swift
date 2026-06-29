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
}
