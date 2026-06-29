//
//  VolumeBrowserModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The volumes read surface: loading (down service vs genuinely empty), search, selection,
//  attachment stamping via the AttachmentIndex, and raw-retaining inspect.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class VolumeBrowserModelTests: XCTestCase {
    func testRefreshLoadsAndStampsAttachedContainers() async {
        let backend = MockBackend(
            containers: [
                ContainerSummary(
                    id: "c1", name: "web", image: "alpine", state: "running",
                    volumeMounts: ["data"])
            ],
            volumes: [VolumeSummary(name: "data"), VolumeSummary(name: "cache")])
        let model = VolumeBrowserModel(backend: backend)

        await model.refresh()

        XCTAssertEqual(model.loadState, .loaded)
        let data = model.allVolumes.first { $0.name == "data" }
        let cache = model.allVolumes.first { $0.name == "cache" }
        XCTAssertEqual(data?.attachedContainers, ["web"])
        XCTAssertEqual(cache?.attachedContainers, [], "an unmounted volume has no attachments")
    }

    func testUnavailableIsDistinctFromEmpty() async {
        let backend = MockBackend(volumes: [])
        backend.failure = BackendError.nonZeroExit(
            command: "container volume list", code: 1, stderr: "Connection refused")
        let model = VolumeBrowserModel(backend: backend)

        await model.refresh()

        guard case .unavailable = model.loadState else {
            return XCTFail("a daemon failure must surface as .unavailable, not an empty list")
        }
        XCTAssertFalse(model.isEmptyButHealthy)
    }

    func testEmptyButHealthyWhenServiceUpButNoVolumes() async {
        let model = VolumeBrowserModel(backend: MockBackend(volumes: []))
        await model.refresh()
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertTrue(model.isEmptyButHealthy)
    }

    func testSearchMatchesNameAndSource() async {
        let backend = MockBackend(volumes: [
            VolumeSummary(name: "data", source: "/srv/data"),
            VolumeSummary(name: "cache", source: "/srv/cache"),
        ])
        let model = VolumeBrowserModel(backend: backend)
        await model.refresh()

        model.searchText = "cache"
        XCTAssertEqual(model.rows.map(\.name), ["cache"])

        model.searchText = "/srv/data"
        XCTAssertEqual(model.rows.map(\.name), ["data"], "source is searchable")
    }

    func testNoMatchesWhenSearchExcludesEverything() async {
        let model = VolumeBrowserModel(backend: MockBackend(volumes: [VolumeSummary(name: "data")]))
        await model.refresh()
        model.searchText = "zzz-not-here"
        XCTAssertTrue(model.noMatches)
        XCTAssertFalse(model.isEmptyButHealthy)
    }

    func testSelectionIsIntersectedWithLoadedRowsOnRefresh() async {
        let backend = MockBackend(volumes: [VolumeSummary(name: "data")])
        let model = VolumeBrowserModel(backend: backend)
        await model.refresh()
        model.selection = ["data", "ghost"]

        await model.refresh()

        XCTAssertEqual(model.selection, ["data"], "stale ids are dropped")
    }

    func testInspectReturnsDecodedValueAndRawPayload() async {
        let backend = MockBackend(volumes: [VolumeSummary(name: "data")])
        let model = VolumeBrowserModel(backend: backend)
        let inspection = await model.inspect(name: "data")
        XCTAssertEqual(inspection.value?.name, "data")
        XCTAssertFalse(inspection.rawJSON.isEmpty)
    }
}
