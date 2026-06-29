//
//  NetworkBrowserModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The networks read surface: loading (down service vs genuinely empty), search, selection,
//  raw-retaining inspect, and the connected-container stamp built from the attachment index.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class NetworkBrowserModelTests: XCTestCase {
    func testRefreshLoadsAndStampsConnectedContainers() async {
        let backend = MockBackend(
            containers: [
                ContainerSummary(
                    id: "c1", name: "web", image: "alpine:latest", state: "running",
                    networkNames: ["default"])
            ],
            networks: [
                NetworkSummary(id: "default", name: "default", isBuiltin: true),
                NetworkSummary(id: "br0", name: "br0"),
            ])
        let model = NetworkBrowserModel(backend: backend)

        await model.refresh()

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.allNetworks.count, 2)
        XCTAssertEqual(
            model.allNetworks.first { $0.name == "default" }?.connectedContainers, ["web"])
        XCTAssertEqual(model.allNetworks.first { $0.name == "br0" }?.connectedContainers, [])
    }

    func testUnavailableIsDistinctFromEmpty() async {
        let backend = MockBackend(networks: [])
        backend.failure = BackendError.nonZeroExit(
            command: "container network list", code: 1, stderr: "Connection refused")
        let model = NetworkBrowserModel(backend: backend)

        await model.refresh()

        guard case .unavailable = model.loadState else {
            return XCTFail("a daemon failure must surface as .unavailable, not an empty list")
        }
        XCTAssertFalse(model.isEmptyButHealthy)
    }

    func testEmptyButHealthyWhenServiceUpButNoNetworks() async {
        let model = NetworkBrowserModel(backend: MockBackend(networks: []))
        await model.refresh()
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertTrue(model.isEmptyButHealthy)
    }

    func testSearchMatchesNameAndSubnet() async {
        let backend = MockBackend(networks: [
            NetworkSummary(id: "default", name: "default", subnet: "192.168.64.0/24"),
            NetworkSummary(id: "br0", name: "br0", subnet: "10.0.0.0/24"),
        ])
        let model = NetworkBrowserModel(backend: backend)
        await model.refresh()

        model.searchText = "br0"
        XCTAssertEqual(model.rows.map(\.name), ["br0"])

        model.searchText = "192.168"
        XCTAssertEqual(model.rows.map(\.name), ["default"], "subnet is searchable")
    }

    func testSelectionIsIntersectedOnRefresh() async {
        let backend = MockBackend(networks: [NetworkSummary(id: "default", name: "default")])
        let model = NetworkBrowserModel(backend: backend)
        await model.refresh()
        model.selection = ["default", "ghost"]

        await model.refresh()

        XCTAssertEqual(model.selection, ["default"], "stale ids are dropped")
    }

    func testInspectReturnsDecodedValue() async {
        let backend = MockBackend(networks: [NetworkSummary(id: "default", name: "default")])
        let model = NetworkBrowserModel(backend: backend)
        let inspection = await model.inspect(name: "default")
        XCTAssertEqual(inspection.value?.name, "default")
    }
}
