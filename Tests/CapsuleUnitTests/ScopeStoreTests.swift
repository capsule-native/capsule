//
//  ScopeStoreTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class ScopeStoreTests: XCTestCase {
    func testInMemoryStoreRoundTrips() {
        let store = InMemoryScopeStore()
        XCTAssertTrue(store.load().isEmpty)
        let scopes = [
            ContainerScope(id: "1", name: "A", stateFilter: .running, searchTerm: "x")
        ]
        store.save(scopes)
        XCTAssertEqual(store.load(), scopes)
    }

    func testInMemoryStoreSeedsInitialScopes() {
        let seed = [ContainerScope(id: "1", name: "A", stateFilter: .all, searchTerm: "")]
        XCTAssertEqual(InMemoryScopeStore(scopes: seed).load(), seed)
    }
}
