//
//  PluginCatalogTypesTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import XCTest

final class PluginCatalogTypesTests: XCTestCase {
    func testPluginInfoIdentifiesByName() {
        let info = PluginInfo(
            name: "buildx",
            path: "/usr/local/libexec/container-plugins/container-buildx")
        XCTAssertEqual(info.id, "buildx")
        XCTAssertEqual(info.name, "buildx")
        XCTAssertEqual(info.path, "/usr/local/libexec/container-plugins/container-buildx")
    }

    func testNoPluginDiscoveryReturnsEmpty() {
        XCTAssertEqual(NoPluginDiscovery().installedPlugins(), [])
    }
}
