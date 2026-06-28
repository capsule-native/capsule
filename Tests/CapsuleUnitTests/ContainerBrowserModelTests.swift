//
//  ContainerBrowserModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class ContainerBrowserModelTests: XCTestCase {
    private func model(
        backend: any ContainerBackend = MockBackend(),
        store: any ScopeStore = InMemoryScopeStore()
    ) -> ContainerBrowserModel {
        ContainerBrowserModel(backend: backend, scopeStore: store)
    }

    func testRefreshLoadsAllContainers() async {
        let m = model()
        await m.refresh()
        XCTAssertEqual(m.loadState, .loaded)
        XCTAssertEqual(m.allContainers.count, 3)
    }

    func testStateFilterNarrowsRows() async {
        let m = model()
        await m.refresh()
        m.stateFilter = .running
        XCTAssertTrue(m.rows.allSatisfy { $0.state == .running })
        XCTAssertEqual(m.rows.count, 2)
    }

    func testSearchMatchesNameImageOrID() async {
        let m = model()
        await m.refresh()
        m.searchText = "postgres"
        XCTAssertEqual(m.rows.map(\.name), ["db"])
    }

    func testRowsAreSortedByName() async {
        let m = model()
        await m.refresh()
        XCTAssertEqual(m.rows.map(\.name), ["cache", "db", "web"])
    }

    func testNoMatchesIsDistinctFromEmptyButHealthy() async {
        let m = model()
        await m.refresh()
        m.searchText = "zzz-nothing"
        XCTAssertTrue(m.noMatches)
        XCTAssertFalse(m.isEmptyButHealthy)
    }

    func testEmptyButHealthyWhenServiceUpButNoContainers() async {
        let m = model(backend: MockBackend(containers: []))
        await m.refresh()
        XCTAssertTrue(m.isEmptyButHealthy)
        XCTAssertFalse(m.noMatches)
    }

    func testRefreshFailureRoutesToUnavailableNotEmpty() async {
        let backend = MockBackend()
        backend.failure = .executableNotFound("container")
        let m = model(backend: backend)
        await m.refresh()
        guard case .unavailable(let detail) = m.loadState else {
            return XCTFail("expected .unavailable, got \(m.loadState)")
        }
        XCTAssertFalse(detail.title.isEmpty)
        XCTAssertTrue(m.allContainers.isEmpty)
        XCTAssertFalse(m.isEmptyButHealthy)  // unavailable != empty-but-healthy
    }

    func testSelectionPrunedToExistingContainersOnRefresh() async {
        let m = model()
        await m.refresh()
        m.selection = ["a1b2c3d4", "ghost-id"]
        await m.refresh()
        XCTAssertEqual(m.selection, ["a1b2c3d4"])
    }

    func testInspectReturnsRawAndDecodedValue() async {
        let m = model()
        await m.refresh()
        let inspection = await m.inspect(id: "a1b2c3d4")
        XCTAssertEqual(inspection.value?.id, "a1b2c3d4")
        XCTAssertFalse(inspection.rawJSON.isEmpty)
    }

    func testSaveActivateAndRemoveScope() async {
        let store = InMemoryScopeStore()
        let m = model(store: store)
        m.stateFilter = .running
        m.searchText = "web"
        m.saveCurrentScope(name: "Web Running")
        XCTAssertEqual(m.savedScopes.count, 1)
        XCTAssertEqual(store.load().count, 1)  // persisted

        m.stateFilter = .all
        m.searchText = ""
        m.activate(m.savedScopes[0])
        XCTAssertEqual(m.stateFilter, .running)
        XCTAssertEqual(m.searchText, "web")

        m.removeScope(m.savedScopes[0])
        XCTAssertTrue(m.savedScopes.isEmpty)
        XCTAssertTrue(store.load().isEmpty)
    }

    func testLoadScopesReadsFromStore() {
        let store = InMemoryScopeStore(scopes: [
            ContainerScope(id: "1", name: "Seed", stateFilter: .stopped, searchTerm: "")
        ])
        let m = model(store: store)
        m.loadScopes()
        XCTAssertEqual(m.savedScopes.map(\.name), ["Seed"])
    }
}
