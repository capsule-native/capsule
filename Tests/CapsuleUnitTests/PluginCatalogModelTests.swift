//
//  PluginCatalogModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import XCTest

private struct FakeDiscovery: PluginDiscovering {
    let plugins: [PluginInfo]
    func installedPlugins() -> [PluginInfo] { plugins }
}

@MainActor
final class PluginCatalogModelTests: XCTestCase {
    private let sample = [
        PluginInfo(name: "buildx", path: "/p/container-buildx"),
        PluginInfo(name: "compose", path: "/p/container-compose"),
    ]

    func testRefreshIsEmptyWhenServiceStopped() {
        let model = PluginCatalogModel(
            discovering: FakeDiscovery(plugins: sample), isServiceRunning: { false })
        model.refresh()
        XCTAssertEqual(model.plugins, [])
    }

    func testRefreshListsPluginsWhenServiceRunning() {
        let model = PluginCatalogModel(
            discovering: FakeDiscovery(plugins: sample), isServiceRunning: { true })
        model.refresh()
        XCTAssertEqual(model.plugins, sample)
    }

    func testTerminalRequestRoutesContainerSubcommand() {
        let model = PluginCatalogModel(
            discovering: FakeDiscovery(plugins: sample), isServiceRunning: { true })
        let request = model.terminalRequest(for: sample[0])
        XCTAssertNil(request.containerID)
        XCTAssertEqual(request.title, "container buildx")
        XCTAssertEqual(request.argv, ["container", "buildx"])
        XCTAssertEqual(request.kind, .runInteractive)
    }
}
