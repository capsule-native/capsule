//
//  NetworkConfigurationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NetworkConfiguration.arguments is the single source of truth for the
//  `container network create` argv: --internal, labels, options, plugin,
//  subnet, subnet-v6, then the name.

import CapsuleBackend
import XCTest

final class NetworkConfigurationTests: XCTestCase {
    func testMinimalArgv() {
        XCTAssertEqual(
            NetworkConfiguration(name: "app-net").arguments, ["network", "create", "app-net"])
    }

    func testSubnetOnly() {
        XCTAssertEqual(
            NetworkConfiguration(name: "app-net", subnet: "10.0.0.0/24").arguments,
            ["network", "create", "--subnet", "10.0.0.0/24", "app-net"])
    }

    func testInternalOnly() {
        XCTAssertEqual(
            NetworkConfiguration(name: "app-net", internal: true).arguments,
            ["network", "create", "--internal", "app-net"])
    }

    func testFullArgvOrdering() {
        let config = NetworkConfiguration(
            name: "app-net", subnet: "10.0.0.0/24", subnetV6: "fd00::/64",
            internal: true, options: ["mtu=1500"], labels: ["env=dev"],
            plugin: "container-network-vmnet")
        XCTAssertEqual(
            config.arguments,
            [
                "network", "create", "--internal",
                "--label", "env=dev",
                "--option", "mtu=1500",
                "--plugin", "container-network-vmnet",
                "--subnet", "10.0.0.0/24",
                "--subnet-v6", "fd00::/64",
                "app-net",
            ])
    }
}
