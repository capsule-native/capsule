//
//  UserDefaultsScopeStore.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The concrete `ScopeStore` for saved container scopes. It lives in the composition root
//  (not the domain) so the persistence key and JSON encoding stay out of `CapsuleDomain`.

import CapsuleDomain
import Foundation

struct UserDefaultsScopeStore: ScopeStore {
    // `UserDefaults` is thread-safe but not yet `Sendable`-annotated; the store conforms
    // to the `Sendable` `ScopeStore` seam, so opt the reference out of the check.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let key = "capsule.containerScopes"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [ContainerScope] {
        guard
            let data = defaults.data(forKey: key),
            let scopes = try? JSONDecoder().decode([ContainerScope].self, from: data)
        else {
            return []
        }
        return scopes
    }

    func save(_ scopes: [ContainerScope]) {
        guard let data = try? JSONEncoder().encode(scopes) else { return }
        defaults.set(data, forKey: key)
    }
}
