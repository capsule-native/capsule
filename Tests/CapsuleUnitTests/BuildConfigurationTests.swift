//
//  BuildConfigurationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

final class BuildConfigurationTests: XCTestCase {
    func testBuildArgvDefaults() {
        let config = BuildConfiguration(
            contextDirectory: URL(fileURLWithPath: "/proj"), tag: "app:dev")
        XCTAssertEqual(config.arguments, ["build", "--tag", "app:dev", "/proj"])
    }

    func testBuildArgvFull() {
        let config = BuildConfiguration(
            contextDirectory: URL(fileURLWithPath: "/proj"), tag: "app:dev",
            dockerfile: "docker/Dockerfile", buildArgs: ["VER=1"], noCache: true,
            plainProgress: true)
        XCTAssertEqual(
            config.arguments,
            [
                "build", "--tag", "app:dev", "--file", "docker/Dockerfile",
                "--build-arg", "VER=1", "--no-cache", "--progress", "plain", "/proj",
            ])
    }

    func testPlainProgressOnly() {
        let config = BuildConfiguration(
            contextDirectory: URL(fileURLWithPath: "/p"), tag: "t:1", plainProgress: true)
        XCTAssertEqual(config.arguments, ["build", "--tag", "t:1", "--progress", "plain", "/p"])
    }
}
