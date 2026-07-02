//
//  RegistrySearchModelTagsTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Tier-2 tests for `RegistrySearchModel`'s tag-picker behaviors: selection loads the
//  namespaced repository's tags exactly once, clearing resets, a 404 maps to its detail
//  and retryTags() recovers, and loadMoreTags appends the next page.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class RegistrySearchModelTagsTests: XCTestCase {

    // MARK: - Helpers

    private func makeModel(mock: MockImageRegistry) -> RegistrySearchModel {
        RegistrySearchModel(
            client: mock, debounceInterval: .milliseconds(20), cacheLifetime: .seconds(300),
            throttleCooldown: .seconds(60))
    }

    private static func tagPage(_ names: [String], hasNext: Bool = false) -> RegistryTagPage {
        RegistryTagPage(
            items: names.map { RegistryTagSummary(name: $0) }, hasNextPage: hasNext)
    }

    /// The repo's bounded-poll idiom: waits (up to ~500ms) for a condition instead of one
    /// oversized sleep, so passing tests stay fast.
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<50 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Selection

    func testSelectOfficialRepositoryLoadsNamespacedTags() async {
        let mock = MockImageRegistry(tagPages: [
            "library/nginx": [1: Self.tagPage(["latest", "alpine"])]
        ])
        let model = makeModel(mock: mock)
        let repository = RegistryRepository(name: "nginx", isOfficial: true)
        model.selectRepository(repository)
        await waitUntil { model.tagState == .loaded }
        XCTAssertEqual(
            mock.lastTagsRepository, "library/nginx",
            "official repositories are addressed via the implicit library namespace")
        XCTAssertEqual(
            model.tags.map(\.name), ["latest", "alpine"],
            "the mapped tags should mirror the seeded page in order")
        XCTAssertEqual(model.selectedRepository, repository, "the selection should stick")
    }

    func testReselectingTheSameRepositoryDoesNotRefetch() async {
        let mock = MockImageRegistry(tagPages: [
            "library/nginx": [1: Self.tagPage(["latest"])]
        ])
        let model = makeModel(mock: mock)
        let repository = RegistryRepository(name: "nginx", isOfficial: true)
        model.selectRepository(repository)
        await waitUntil { model.tagState == .loaded }
        XCTAssertEqual(mock.tagsCallCount, 1, "the first selection fetches the tags")

        model.selectRepository(repository)
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(
            mock.tagsCallCount, 1, "re-selecting the already-selected repository is a no-op")
        XCTAssertEqual(model.tagState, .loaded, "the loaded tags should remain in place")
    }

    func testClearSelectionResetsTagsAndState() async {
        let mock = MockImageRegistry(tagPages: [
            "library/nginx": [1: Self.tagPage(["latest"])]
        ])
        let model = makeModel(mock: mock)
        model.selectRepository(RegistryRepository(name: "nginx", isOfficial: true))
        await waitUntil { model.tagState == .loaded }

        model.clearSelection()
        XCTAssertNil(model.selectedRepository, "clearing should drop the selection")
        XCTAssertEqual(model.tags, [], "clearing should drop the loaded tags")
        XCTAssertEqual(model.tagState, .idle, "clearing should reset the tag state to idle")
        XCTAssertFalse(model.hasMoreTags, "clearing should reset the pagination flag")
    }

    // MARK: - 404 & retry

    func testTagsNotFoundMapsToDetailAndRetryRecovers() async {
        let mock = MockImageRegistry(tagPages: [
            "library/nginx": [1: Self.tagPage(["latest"])]
        ])
        mock.failure = .httpStatus(code: 404, message: nil)
        let model = makeModel(mock: mock)
        model.selectRepository(RegistryRepository(name: "nginx", isOfficial: true))
        await waitUntil {
            if case .unavailable = model.tagState { return true }
            return false
        }
        guard case .unavailable(let detail) = model.tagState else {
            XCTFail("an http 404 should surface as unavailable")
            return
        }
        XCTAssertEqual(
            detail.title, "Repository not found", "a 404 maps to the not-found headline")

        mock.failure = nil
        model.retryTags()
        await waitUntil { model.tagState == .loaded }
        XCTAssertEqual(model.tagState, .loaded, "retrying after the failure clears should load")
        XCTAssertEqual(
            model.tags.map(\.name), ["latest"], "the retry should surface the seeded tags")
    }

    // MARK: - Pagination

    func testLoadMoreTagsAppendsNextPageAndFlipsHasMore() async {
        let mock = MockImageRegistry(tagPages: [
            "library/nginx": [
                1: Self.tagPage(["latest", "1.31.2"], hasNext: true),
                2: Self.tagPage(["alpine"], hasNext: false),
            ]
        ])
        let model = makeModel(mock: mock)
        model.selectRepository(RegistryRepository(name: "nginx", isOfficial: true))
        await waitUntil { model.tagState == .loaded }
        XCTAssertTrue(model.hasMoreTags, "page one advertises a next page")

        model.loadMoreTags()
        await waitUntil { model.tags.count == 3 }
        XCTAssertEqual(
            model.tags.map(\.name), ["latest", "1.31.2", "alpine"],
            "the next tag page should append in order without duplicates")
        XCTAssertEqual(mock.lastTagsPage, 2, "load more should request the second page")
        XCTAssertFalse(model.hasMoreTags, "the last page should flip the load-more flag off")
        XCTAssertEqual(mock.tagsCallCount, 2, "exactly two pages were fetched")
    }
}
