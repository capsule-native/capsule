//
//  NetworkTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The domain Network model: mapping a backend NetworkSummary into a UI-friendly value,
//  including the builtin flag and the derived connected-container stamp.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

final class NetworkTests: XCTestCase {
    func testInitFromSummaryMapsEveryField() {
        let summary = NetworkSummary(
            id: "default", name: "default", mode: "nat", gateway: "192.168.64.1",
            subnet: "192.168.64.0/24", plugin: "container-network-vmnet",
            ipv6Subnet: "fdb6:5eb:8ee:85cf::/64",
            labels: ["com.apple.container.resource.role": "builtin"],
            createdAt: "2026-06-27T12:15:24Z", isBuiltin: true)

        let network = Network(summary: summary, connectedContainers: ["web"])

        XCTAssertEqual(network.id, "default")
        XCTAssertEqual(network.name, "default")
        XCTAssertEqual(network.mode, "nat")
        XCTAssertEqual(network.plugin, "container-network-vmnet")
        XCTAssertEqual(network.ipv4Subnet, "192.168.64.0/24")
        XCTAssertEqual(network.ipv4Gateway, "192.168.64.1")
        XCTAssertEqual(network.ipv6Subnet, "fdb6:5eb:8ee:85cf::/64")
        XCTAssertTrue(network.isBuiltin)
        XCTAssertEqual(network.connectedContainers, ["web"])
        XCTAssertNotNil(network.createdAt)
        XCTAssertFalse(network.internal, "summary carries no internal flag; defaults to false")
    }

    func testConnectedContainersDefaultEmpty() {
        let network = Network(summary: NetworkSummary(id: "br0", name: "br0"))
        XCTAssertEqual(network.connectedContainers, [])
        XCTAssertFalse(network.isBuiltin)
    }
}
