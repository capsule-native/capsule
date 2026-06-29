//
//  MachineConfigurationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  MachineConfiguration.arguments is the single source of truth for the
//  `container machine create` argv: flags in order, then image as trailing
//  positional.

import CapsuleBackend
import XCTest

final class MachineConfigurationTests: XCTestCase {
    func test_minimal_imageOnly() {
        let c = MachineConfiguration(image: "alpine:3.22")
        XCTAssertEqual(c.arguments, ["machine", "create", "alpine:3.22"])
    }

    func test_full_orderedFlagsThenImage() {
        let c = MachineConfiguration(
            image: "ubuntu:24.04", name: "dev", cpus: 4, memory: "8G", homeMount: "ro",
            arch: "arm64", os: "linux", platform: "linux/arm64", setDefault: true, noBoot: true)
        XCTAssertEqual(
            c.arguments,
            [
                "machine", "create",
                "--name", "dev", "--cpus", "4", "--memory", "8G", "--home-mount", "ro",
                "--arch", "arm64", "--os", "linux", "--platform", "linux/arm64",
                "--set-default", "--no-boot",
                "ubuntu:24.04",
            ])
    }

    func test_settings_nameAndTokens() {
        let s = MachineSettings(cpus: 4, memory: "8G", homeMount: "ro")
        XCTAssertEqual(
            s.arguments(name: "dev"),
            ["machine", "set", "--name", "dev", "cpus=4", "memory=8G", "home-mount=ro"])
    }

    func test_settings_omitName_partial() {
        let s = MachineSettings(memory: "2G")
        XCTAssertEqual(
            s.arguments(name: nil),
            ["machine", "set", "memory=2G"])
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(MachineSettings().isEmpty)
    }
}
