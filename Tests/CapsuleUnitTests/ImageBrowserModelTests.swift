//
//  ImageBrowserModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The images read surface: loading (distinguishing a down service from a genuinely empty
//  list), search, sort, the dangling filter, selection, and raw-retaining inspect.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class ImageBrowserModelTests: XCTestCase {
    private func image(
        _ ref: String, size: Int64 = 100, created: String? = nil, digest: String = "sha256:a"
    )
        -> ImageSummary
    {
        ImageSummary(
            id: digest, reference: ref, sizeBytes: size, digest: digest, createdAt: created)
    }

    func testRefreshLoadsAndMapsImages() async {
        let backend = MockBackend(images: [
            image("alpine:latest"), image("postgres:16", digest: "sha256:b"),
        ])
        let model = ImageBrowserModel(backend: backend)

        await model.refresh()

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.allImages.count, 2)
        XCTAssertEqual(Set(model.allImages.map(\.reference)), ["alpine:latest", "postgres:16"])
    }

    func testUnavailableIsDistinctFromEmpty() async {
        let backend = MockBackend(images: [])
        backend.failure = BackendError.nonZeroExit(
            command: "container image list", code: 1, stderr: "Connection refused")
        let model = ImageBrowserModel(backend: backend)

        await model.refresh()

        guard case .unavailable = model.loadState else {
            return XCTFail("a daemon failure must surface as .unavailable, not an empty list")
        }
        XCTAssertFalse(model.isEmptyButHealthy)
    }

    func testEmptyButHealthyWhenServiceUpButNoImages() async {
        let model = ImageBrowserModel(backend: MockBackend(images: []))
        await model.refresh()
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertTrue(model.isEmptyButHealthy)
    }

    func testSearchMatchesReferenceAndDigest() async {
        let backend = MockBackend(images: [
            image("alpine:latest", digest: "sha256:aaa111"),
            image("postgres:16", digest: "sha256:bbb222"),
        ])
        let model = ImageBrowserModel(backend: backend)
        await model.refresh()

        model.searchText = "postgres"
        XCTAssertEqual(model.rows.map(\.reference), ["postgres:16"])

        model.searchText = "aaa111"
        XCTAssertEqual(model.rows.map(\.reference), ["alpine:latest"], "digest is searchable")
    }

    func testSortBySizeDescendingThenName() async {
        let backend = MockBackend(images: [
            image("a:1", size: 10, digest: "sha256:1"),
            image("b:1", size: 30, digest: "sha256:2"),
            image("c:1", size: 20, digest: "sha256:3"),
        ])
        let model = ImageBrowserModel(backend: backend)
        await model.refresh()

        model.sort = .size
        XCTAssertEqual(model.rows.map(\.reference), ["b:1", "c:1", "a:1"])

        model.sort = .name
        XCTAssertEqual(model.rows.map(\.reference), ["a:1", "b:1", "c:1"])
    }

    func testSortByCreatedNewestFirstWithUndatedLast() async {
        let backend = MockBackend(images: [
            image("old:1", created: "2026-01-01T00:00:00Z", digest: "sha256:1"),
            image("new:1", created: "2026-06-01T00:00:00Z", digest: "sha256:2"),
            image("undated:1", created: nil, digest: "sha256:3"),
        ])
        let model = ImageBrowserModel(backend: backend)
        await model.refresh()

        model.sort = .created
        XCTAssertEqual(model.rows.map(\.reference), ["new:1", "old:1", "undated:1"])
    }

    func testDanglingOnlyFilter() async {
        let backend = MockBackend(images: [
            image("alpine:latest", digest: "sha256:1"),
            image("<none>:<none>", digest: "sha256:2"),
        ])
        let model = ImageBrowserModel(backend: backend)
        await model.refresh()

        model.showDanglingOnly = true
        XCTAssertEqual(model.rows.map(\.id), ["sha256:2"])
    }

    func testNoMatchesWhenSearchExcludesEverything() async {
        let model = ImageBrowserModel(backend: MockBackend(images: [image("alpine:latest")]))
        await model.refresh()
        model.searchText = "zzz-not-here"
        XCTAssertTrue(model.noMatches)
        XCTAssertFalse(model.isEmptyButHealthy)
    }

    func testSelectionIsIntersectedWithLoadedRowsOnRefresh() async {
        let backend = MockBackend(images: [
            image("alpine:latest"), image("postgres:16", digest: "sha256:b"),
        ])
        let model = ImageBrowserModel(backend: backend)
        await model.refresh()
        model.selection = ["alpine:latest", "ghost:1"]

        await model.refresh()

        XCTAssertEqual(model.selection, ["alpine:latest"], "stale ids are dropped")
    }

    func testInspectReturnsDecodedValueAndRawPayload() async {
        let backend = MockBackend(images: [image("alpine:latest")])
        let model = ImageBrowserModel(backend: backend)
        let inspection = await model.inspect(reference: "alpine:latest")
        XCTAssertEqual(inspection.value?.reference, "alpine:latest")
        XCTAssertFalse(inspection.rawJSON.isEmpty)
    }
}
