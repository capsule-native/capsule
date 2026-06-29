//
//  VolumeConfigurationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  VolumeConfiguration.arguments is the single source of truth for the
//  `container volume create` argv: labels, then opts, then size, then the name.

import CapsuleBackend
import XCTest

final class VolumeConfigurationTests: XCTestCase {
    func testMinimalArgv() {
        XCTAssertEqual(VolumeConfiguration(name: "data").arguments, ["volume", "create", "data"])
    }

    func testSizeOnlyUsesShortFlag() {
        XCTAssertEqual(
            VolumeConfiguration(name: "data", size: "512M").arguments,
            ["volume", "create", "-s", "512M", "data"])
    }

    func testFullArgvOrdersLabelsThenOptsThenSizeThenName() {
        let config = VolumeConfiguration(
            name: "data", size: "10G",
            options: ["type=ext4", "journal=ordered"],
            labels: ["env=dev", "team=infra"])
        XCTAssertEqual(
            config.arguments,
            [
                "volume", "create",
                "--label", "env=dev", "--label", "team=infra",
                "--opt", "type=ext4", "--opt", "journal=ordered",
                "-s", "10G", "data",
            ])
    }

    func testEquatable() {
        XCTAssertEqual(
            VolumeConfiguration(name: "data", size: "1G"),
            VolumeConfiguration(name: "data", size: "1G"))
    }
}
