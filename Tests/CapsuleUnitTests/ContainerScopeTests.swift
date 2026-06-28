//
//  ContainerScopeTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class ContainerScopeTests: XCTestCase {
    func testStateFilterMatching() {
        XCTAssertTrue(ContainerStateFilter.all.matches(.stopped))
        XCTAssertTrue(ContainerStateFilter.running.matches(.running))
        XCTAssertFalse(ContainerStateFilter.running.matches(.stopped))
        XCTAssertTrue(ContainerStateFilter.stopped.matches(.stopped))
        XCTAssertTrue(ContainerStateFilter.created.matches(.created))
    }

    func testBuiltInScopesAreAllRunningStopped() {
        XCTAssertEqual(
            ContainerScope.builtIns.map(\.stateFilter), [.all, .running, .stopped])
        XCTAssertEqual(ContainerScope.all.name, "All")
    }

    func testScopeRoundTripsThroughCodable() throws {
        let scope = ContainerScope(
            id: "x", name: "My View", stateFilter: .running, searchTerm: "web")
        let data = try JSONEncoder().encode([scope])
        let decoded = try JSONDecoder().decode([ContainerScope].self, from: data)
        XCTAssertEqual(decoded, [scope])
    }
}
