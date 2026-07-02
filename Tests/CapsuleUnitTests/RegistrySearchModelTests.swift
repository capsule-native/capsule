//
//  RegistrySearchModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Tier-2 tests for `RegistrySearchModel`'s repository-search behaviors: the minimum query
//  length, debounce coalescing, supersede/cancellation, the (query, page) cache and its
//  TTL, pagination, the 429 throttle cooldown, and failure mapping. Tag behaviors live in
//  RegistrySearchModelTagsTests.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class RegistrySearchModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeModel(
        mock: MockImageRegistry,
        debounceInterval: Duration = .milliseconds(20),
        cacheLifetime: Duration = .seconds(300),
        throttleCooldown: Duration = .seconds(60)
    ) -> RegistrySearchModel {
        RegistrySearchModel(
            client: mock, debounceInterval: debounceInterval, cacheLifetime: cacheLifetime,
            throttleCooldown: throttleCooldown)
    }

    private static func page(
        _ names: [String], hasNext: Bool = false
    ) -> RegistryRepositoryPage {
        RegistryRepositoryPage(
            items: names.map { RegistryRepositorySummary(name: $0) }, hasNextPage: hasNext)
    }

    /// The repo's bounded-poll idiom: waits (up to ~500ms) for a condition instead of one
    /// oversized sleep, so passing tests stay fast.
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<50 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Minimum query length

    func testSingleCharacterQueryNeverReachesTheClient() async {
        let mock = MockImageRegistry(searchPages: ["*": [1: Self.page(["nginx"])]])
        let model = makeModel(mock: mock)
        model.searchText = "a"
        // Give the debounce ample time to have fired if it were going to.
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(
            mock.searchCallCount, 0, "queries below the minimum length must not hit the network")
        XCTAssertEqual(model.loadState, .idle, "a too-short query should leave the surface idle")
    }

    func testWhitespacePaddedShortQueryStaysIdle() async {
        let mock = MockImageRegistry(searchPages: ["*": [1: Self.page(["nginx"])]])
        let model = makeModel(mock: mock)
        model.searchText = "  a  "
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(
            mock.searchCallCount, 0, "the minimum length applies to the trimmed query")
        XCTAssertEqual(model.loadState, .idle, "padding whitespace must not defeat the minimum")
    }

    // MARK: - Debounce & supersede

    func testRapidEditsCoalesceIntoOneSearch() async {
        let mock = MockImageRegistry(searchPages: ["*": [1: Self.page(["nginx"])]])
        let model = makeModel(mock: mock)
        model.searchText = "n"
        model.searchText = "ng"
        model.searchText = "ngi"
        model.searchText = "nginx"
        await waitUntil { model.loadState == .loaded }
        XCTAssertEqual(
            mock.searchCallCount, 1, "the debounce should coalesce rapid edits into one call")
        XCTAssertEqual(
            mock.lastSearchQuery, "nginx", "only the final query should reach the client")
    }

    func testEditDuringDebounceSupersedesPendingQuery() async {
        let mock = MockImageRegistry(searchPages: ["*": [1: Self.page(["nginx"])]])
        let model = makeModel(mock: mock)
        model.searchText = "first"
        model.searchText = "second"
        await waitUntil { model.loadState == .loaded }
        XCTAssertEqual(
            mock.searchQueries, ["second"],
            "a query superseded during the debounce window must never reach the client")
    }

    // MARK: - In-flight cancellation

    func testEditDuringFlightCancelsAndOnlyShowsTheNewPage() async {
        let mock = MockImageRegistry(searchPages: [
            "alpha": [1: Self.page(["alpha-repo"])],
            "beta": [1: Self.page(["beta-repo"])],
        ])
        mock.responseDelay = .milliseconds(150)
        let model = makeModel(mock: mock)
        model.searchText = "alpha"
        await waitUntil { mock.searchCallCount == 1 }
        model.searchText = "beta"
        for _ in 0..<50 where model.loadState != .loaded {
            XCTAssertFalse(
                model.repositories.contains { $0.name == "alpha-repo" },
                "a cancelled request's items must never surface")
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(mock.searchCallCount, 2, "both queries should reach the client once each")
        XCTAssertEqual(
            model.repositories.map(\.name), ["beta-repo"],
            "only the superseding query's results should be shown")
    }

    // MARK: - Cache

    func testRepeatSearchIsServedFromCacheWithoutRefetch() async {
        let mock = MockImageRegistry(searchPages: ["nginx": [1: Self.page(["nginx"])]])
        let model = makeModel(mock: mock)
        model.searchText = "nginx"
        await waitUntil { model.loadState == .loaded }
        XCTAssertEqual(mock.searchCallCount, 1, "the first search hits the network")

        model.searchText = ""
        XCTAssertEqual(model.loadState, .idle, "clearing the query should reset to idle")
        XCTAssertEqual(model.repositories, [], "clearing the query should clear the rows")

        model.searchText = "nginx"
        await waitUntil { model.loadState == .loaded }
        XCTAssertEqual(
            mock.searchCallCount, 1, "a fresh cache entry should answer without a network call")
        XCTAssertEqual(
            model.repositories.map(\.name), ["nginx"],
            "the cached page should repopulate the rows")
    }

    func testExpiredCacheEntryRefetches() async {
        let mock = MockImageRegistry(searchPages: ["nginx": [1: Self.page(["nginx"])]])
        let model = makeModel(mock: mock, cacheLifetime: .milliseconds(30))
        model.searchText = "nginx"
        await waitUntil { model.loadState == .loaded }
        model.searchText = ""
        try? await Task.sleep(for: .milliseconds(60))
        model.searchText = "nginx"
        await waitUntil { model.loadState == .loaded && mock.searchCallCount == 2 }
        XCTAssertEqual(
            mock.searchCallCount, 2, "an expired cache entry must fall through to the network")
    }

    // MARK: - Pagination

    func testLoadMoreAppendsNextPageAndStopsAtTheEnd() async {
        let mock = MockImageRegistry(searchPages: [
            "nginx": [
                1: Self.page(["nginx", "nginx-unprivileged"], hasNext: true),
                2: Self.page(["nginx-exporter"], hasNext: false),
            ]
        ])
        let model = makeModel(mock: mock)
        model.searchText = "nginx"
        await waitUntil { model.loadState == .loaded }
        XCTAssertTrue(
            model.hasMoreRepositories, "page one advertises a next page, so load more is offered")

        model.loadMoreRepositories()
        await waitUntil { model.repositories.count == 3 }
        XCTAssertEqual(
            model.repositories.map(\.name), ["nginx", "nginx-unprivileged", "nginx-exporter"],
            "the next page should append in order without duplicates")
        XCTAssertEqual(mock.lastSearchPage, 2, "load more should request the second page")
        XCTAssertFalse(
            model.hasMoreRepositories, "the last page should flip the load-more affordance off")

        model.loadMoreRepositories()
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(
            mock.searchCallCount, 2, "loading more past the last page must be a no-op")
        XCTAssertEqual(
            model.repositories.count, 3, "a no-op load more must not change the rows")
    }

    // MARK: - Throttle

    func testRateLimitEntersThrottledAndCooldownSuppressesRetries() async {
        let mock = MockImageRegistry(searchPages: ["*": [1: Self.page(["nginx"])]])
        mock.failure = .rateLimited(retryAfterSeconds: nil)
        let model = makeModel(mock: mock, throttleCooldown: .seconds(60))
        model.searchText = "nginx"
        await waitUntil { model.loadState == .throttled }
        XCTAssertEqual(model.loadState, .throttled, "an http 429 should surface as throttled")
        XCTAssertEqual(mock.searchCallCount, 1, "the 429 came from exactly one request")

        mock.failure = nil
        model.searchText = "redis"
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(
            model.loadState, .throttled,
            "edits during the cooldown stay throttled instead of retrying")
        XCTAssertEqual(
            mock.searchCallCount, 1,
            "the cooldown must suppress network calls, proving there is no tight retry loop")
    }

    func testThrottleCooldownExpiresAndSearchResumes() async {
        let mock = MockImageRegistry(searchPages: ["*": [1: Self.page(["redis"])]])
        mock.failure = .rateLimited(retryAfterSeconds: nil)
        let model = makeModel(mock: mock, throttleCooldown: .milliseconds(30))
        model.searchText = "nginx"
        await waitUntil { model.loadState == .throttled }

        mock.failure = nil
        try? await Task.sleep(for: .milliseconds(60))
        model.searchText = "redis"
        await waitUntil { model.loadState == .loaded }
        XCTAssertEqual(model.loadState, .loaded, "searching resumes once the cooldown lapses")
        XCTAssertEqual(
            mock.searchCallCount, 2, "the post-cooldown edit should reach the network again")
    }

    // MARK: - Failure mapping

    func testNetworkFailureMapsToUnavailableDetail() async {
        let mock = MockImageRegistry()
        mock.failure = .network(message: "offline")
        let model = makeModel(mock: mock)
        model.searchText = "nginx"
        await waitUntil {
            if case .unavailable = model.loadState { return true }
            return false
        }
        guard case .unavailable(let detail) = model.loadState else {
            XCTFail("a network failure should surface as unavailable")
            return
        }
        XCTAssertEqual(
            detail.title, "Couldn't reach Docker Hub",
            "a network failure maps to the reachability headline")
    }

    // MARK: - Load More coherence (review regressions)

    func testLoadMoreDuringPendingEditNeitherMixesQueriesNorKillsTheSearch() async {
        let mock = MockImageRegistry(searchPages: [
            "nginx": [1: Self.page(["nginx"], hasNext: true), 2: Self.page(["nginx-two"])],
            "redis": [1: Self.page(["redis"])],
        ])
        let model = makeModel(mock: mock, debounceInterval: .milliseconds(60))
        model.searchText = "nginx"
        await waitUntil { model.loadState == .loaded }

        // Edit the query, then click Load More inside the debounce window.
        model.searchText = "redis"
        model.loadMoreRepositories()

        await waitUntil { mock.lastSearchQuery == "redis" && model.loadState == .loaded }
        XCTAssertEqual(
            model.repositories.map(\.name), ["redis"],
            "load-more during a pending edit must neither append a foreign page nor cancel the edit's search"
        )
        XCTAssertEqual(
            mock.searchQueries, ["nginx", "redis"],
            "the stale-query page 2 must never be requested")
    }

    func testFailedLoadMoreKeepsTheLoadedRowsAndRetries() async {
        let mock = MockImageRegistry(searchPages: [
            "nginx": [1: Self.page(["nginx"], hasNext: true), 2: Self.page(["nginx-two"])]
        ])
        let model = makeModel(mock: mock)
        model.searchText = "nginx"
        await waitUntil { model.loadState == .loaded }

        mock.failure = .httpStatus(code: 500, message: nil)
        model.loadMoreRepositories()
        await waitUntil { model.loadMoreFailure != nil }
        XCTAssertEqual(model.loadState, .loaded, "a failed page append must not blank the pane")
        XCTAssertEqual(
            model.repositories.map(\.name), ["nginx"], "the loaded rows must stay visible")

        mock.failure = nil
        model.loadMoreRepositories()
        await waitUntil { model.repositories.count == 2 }
        XCTAssertEqual(
            model.repositories.map(\.name), ["nginx", "nginx-two"],
            "the same affordance retries the append once the failure clears")
        XCTAssertNil(model.loadMoreFailure, "a successful append clears the inline failure")
    }

    func testThrottledLoadMoreStaysLoadedAndNeverTightLoops() async {
        let mock = MockImageRegistry(searchPages: [
            "nginx": [1: Self.page(["nginx"], hasNext: true), 2: Self.page(["nginx-two"])]
        ])
        let model = makeModel(mock: mock, throttleCooldown: .seconds(60))
        model.searchText = "nginx"
        await waitUntil { model.loadState == .loaded }

        mock.failure = .rateLimited(retryAfterSeconds: nil)
        model.loadMoreRepositories()
        await waitUntil { model.loadMoreFailure != nil }
        XCTAssertEqual(
            model.loadState, .loaded, "a 429 during load-more must not hide the loaded rows")
        XCTAssertEqual(
            model.loadMoreFailure?.title, "Docker Hub is busy",
            "the inline notice carries the throttle copy")

        // Retrying during the cooldown must not touch the network.
        mock.failure = nil
        let callsBefore = mock.searchCallCount
        model.loadMoreRepositories()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(
            mock.searchCallCount, callsBefore,
            "the cooldown suppresses further network calls — no tight retry loop")
        XCTAssertEqual(model.loadState, .loaded, "the rows remain visible throughout")
    }

    // MARK: - searchNow()

    func testSearchNowBypassesTheDebounce() async {
        let mock = MockImageRegistry(searchPages: ["*": [1: Self.page(["nginx"])]])
        // A debounce far longer than the test: only searchNow() can have fired the call.
        let model = makeModel(mock: mock, debounceInterval: .seconds(60))
        model.searchText = "nginx"
        model.searchNow()
        await waitUntil { model.loadState == .loaded }
        XCTAssertEqual(
            mock.searchCallCount, 1, "searchNow should fire without waiting out the debounce")
        XCTAssertEqual(
            mock.lastSearchQuery, "nginx", "searchNow should search the current trimmed query")
    }
}
