//
//  ScopeStore.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Concrete
//  persistence (UserDefaults) lives in the composition root so the domain owns no
//  storage-key knowledge; this file defines only the seam and an in-memory double.

import Foundation

/// Persists the user's saved container scopes. Injected into ``ContainerBrowserModel`` so
/// the domain stays free of any concrete persistence and remains unit-testable.
public protocol ScopeStore: Sendable {
    func load() -> [ContainerScope]
    func save(_ scopes: [ContainerScope])
}

/// A thread-safe, in-memory ``ScopeStore`` — the model's default (ephemeral) and the
/// test double.
public final class InMemoryScopeStore: ScopeStore, @unchecked Sendable {
    private let lock = NSLock()
    private var scopes: [ContainerScope]

    public init(scopes: [ContainerScope] = []) {
        self.scopes = scopes
    }

    public func load() -> [ContainerScope] {
        lock.lock()
        defer { lock.unlock() }
        return scopes
    }

    public func save(_ scopes: [ContainerScope]) {
        lock.lock()
        defer { lock.unlock() }
        self.scopes = scopes
    }
}
