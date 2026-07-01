//
//  CommandCatalogTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import CapsuleDomain
import XCTest

@testable import CapsuleUI

@MainActor
final class CommandCatalogTests: XCTestCase {
    private func makeContext(
        runPresetStore: any PresetStore = InMemoryPresetStore(),
        plugins: any PluginDiscovering = NoPluginDiscovery()
    ) -> (CommandContext, ContainerBrowserModel, ImageBrowserModel, RunModel, PluginCatalogModel) {
        let backend = MockBackend()
        let taskCenter = TaskCenter()
        let shell = ShellState()
        let containers = ContainerBrowserModel(backend: backend)
        let images = ImageBrowserModel(backend: backend)
        let run = RunModel(backend: backend, taskCenter: taskCenter, presetStore: runPresetStore)
        let build = BuildModel(backend: backend, taskCenter: taskCenter)
        let lifecycle = ContainerLifecycleModel(backend: backend)
        let system = SystemStatusModel(backend: backend)
        let pluginCatalog = PluginCatalogModel(discovering: plugins, isServiceRunning: { true })
        let actions = ShellActions(recover: { _ in }, stopServices: {})
        let ctx = CommandContext(
            shell: shell,
            systemModel: system,
            imageBrowserModel: images,
            containerBrowserModel: containers,
            lifecycleModel: lifecycle,
            runModel: run,
            buildModel: build,
            pluginCatalog: pluginCatalog,
            actions: actions,
            followLogs: {})
        return (ctx, containers, images, run, pluginCatalog)
    }

    private func enabled(_ id: String, in ctx: CommandContext) -> Bool {
        CommandCatalog.actions(ctx).first { $0.id == id }!.isEnabled
    }

    func testThirteenFixedActions() {
        let (ctx, _, _, _, _) = makeContext()
        let fixed = CommandCatalog.actions(ctx).filter {
            !$0.id.hasPrefix("preset-") && !$0.id.hasPrefix("plugin-")
        }
        XCTAssertEqual(fixed.count, 13)
        XCTAssertTrue(fixed.contains { $0.id == "raw-command-preview" })
        XCTAssertTrue(fixed.contains { $0.id == "toggle-inspector" })
    }

    func testContainerSelectionGatesActions() {
        let (ctx, containers, _, _, _) = makeContext()
        XCTAssertFalse(enabled("exec-shell", in: ctx))
        XCTAssertFalse(enabled("export-container", in: ctx))
        containers.selection = ["c1"]
        XCTAssertTrue(enabled("exec-shell", in: ctx))
        XCTAssertTrue(enabled("export-container", in: ctx))
    }

    func testImageSelectionGatesRun() {
        let (ctx, _, images, _, _) = makeContext()
        XCTAssertFalse(enabled("run-selected-image", in: ctx))
        images.selection = ["nginx:latest"]
        XCTAssertTrue(enabled("run-selected-image", in: ctx))
    }

    func testNavigationActionsAlwaysEnabled() {
        let (ctx, _, _, _, _) = makeContext()
        XCTAssertTrue(enabled("open-system-logs", in: ctx))
        XCTAssertTrue(enabled("reclaim-disk", in: ctx))
        XCTAssertTrue(enabled("toggle-inspector", in: ctx))
        XCTAssertTrue(enabled("raw-command-preview", in: ctx))
    }

    func testRunPresetSurfacesAsAction() {
        let (ctx, _, _, run, _) = makeContext()
        run.savePreset(name: "web")
        let actions = CommandCatalog.actions(ctx)
        XCTAssertTrue(actions.contains { $0.id.hasPrefix("preset-run-") })
        XCTAssertTrue(actions.contains { $0.title == "Run Preset: web" })
    }

    func testPluginSurfacesAsActionAfterRefresh() {
        let (ctx, _, _, _, pluginCatalog) = makeContext(plugins: OnePlugin())
        XCTAssertFalse(CommandCatalog.actions(ctx).contains { $0.id == "plugin-compose" })
        pluginCatalog.refresh()
        XCTAssertTrue(CommandCatalog.actions(ctx).contains { $0.id == "plugin-compose" })
    }

    func testRawCommandPreviewSeedPrefersContainerThenImageThenNil() async {
        let (ctx, containers, images, run, _) = makeContext()
        let action = CommandCatalog.actions(ctx).first { $0.id == "raw-command-preview" }!

        func console() -> CommandInvocation? {
            guard case let .console(seed: seed)? = ctx.shell.pendingSheet else {
                XCTFail("Expected shell.pendingSheet to be .console")
                return nil
            }
            return seed
        }

        // Neither a container nor an image selected: no seed.
        action.run()
        XCTAssertNil(console())

        // A container selected: seed is that container's exec invocation.
        containers.selection = ["c1"]
        ctx.shell.pendingSheet = nil
        action.run()
        XCTAssertEqual(console(), ctx.lifecycleModel.execInvocation(id: "c1"))

        // Both a container and an image selected: the container still wins.
        await images.refresh()
        let image = images.allImages.first!
        images.selection = [image.id]
        ctx.shell.pendingSheet = nil
        action.run()
        XCTAssertEqual(console(), ctx.lifecycleModel.execInvocation(id: "c1"))

        // No container, only an image selected: seed is the image's run invocation.
        containers.selection = []
        ctx.shell.pendingSheet = nil
        action.run()
        XCTAssertEqual(console(), run.runInvocation(forImage: image.reference))
    }

    func testShortcutDisplay() {
        XCTAssertEqual(CommandShortcut("r", modifiers: [.shift, .command]).display, "⇧⌘R")
        XCTAssertEqual(
            CommandShortcut("k", modifiers: [.shift, .command]),
            CommandShortcut("k", modifiers: [.shift, .command]))
    }
}

private struct OnePlugin: PluginDiscovering {
    func installedPlugins() -> [PluginInfo] {
        [
            PluginInfo(
                name: "compose", path: "/usr/local/libexec/container-plugins/container-compose")
        ]
    }
}
