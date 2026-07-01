//
//  CommandCatalog.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The single source of truth for every power-user action. Both the ⌘K palette and the
//  menu bar render `CommandCatalog.actions(_:)`, so the two surfaces cannot drift. Pure
//  ranking lives in Domain (`FuzzyMatch`); enablement and `run` closures live here because
//  they touch UI state (`ShellState`/`ShellActions`).

import CapsuleDomain
import SwiftUI

/// A keyboard shortcut for a command action (rendered by the menu and shown in the palette).
public struct CommandShortcut: Equatable {
    public let key: KeyEquivalent
    public let modifiers: EventModifiers

    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) {
        self.key = key
        self.modifiers = modifiers
    }

    /// `KeyEquivalent` is not reliably `Equatable` across SDKs, so compare its character.
    public static func == (lhs: CommandShortcut, rhs: CommandShortcut) -> Bool {
        lhs.key.character == rhs.key.character && lhs.modifiers == rhs.modifiers
    }

    /// A glyph string like `⇧⌘R` for palette rows.
    public var display: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += String(key.character).uppercased()
        return result
    }
}

/// One command surfaced in the palette and the menu bar.
public struct CommandAction: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let symbol: String
    public let shortcut: CommandShortcut?
    public let isEnabled: Bool
    public let run: () -> Void

    public init(
        id: String,
        title: String,
        subtitle: String?,
        symbol: String,
        shortcut: CommandShortcut?,
        isEnabled: Bool,
        run: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.run = run
    }
}

/// The live app state a command needs. Built once in `AppEnvironment.live()` and threaded
/// into both `CapsuleCommands` (menus) and `CommandPaletteView` (palette).
@MainActor
public struct CommandContext {
    public var shell: ShellState
    public var systemModel: SystemStatusModel
    public var imageBrowserModel: ImageBrowserModel
    public var containerBrowserModel: ContainerBrowserModel
    public var lifecycleModel: ContainerLifecycleModel
    public var runModel: RunModel
    public var buildModel: BuildModel
    public var pluginCatalog: PluginCatalogModel
    public var actions: ShellActions
    /// Begins log capture for the selected container and reveals the logs surface.
    public var followLogs: () -> Void

    public init(
        shell: ShellState,
        systemModel: SystemStatusModel,
        imageBrowserModel: ImageBrowserModel,
        containerBrowserModel: ContainerBrowserModel,
        lifecycleModel: ContainerLifecycleModel,
        runModel: RunModel,
        buildModel: BuildModel,
        pluginCatalog: PluginCatalogModel,
        actions: ShellActions,
        followLogs: @escaping () -> Void
    ) {
        self.shell = shell
        self.systemModel = systemModel
        self.imageBrowserModel = imageBrowserModel
        self.containerBrowserModel = containerBrowserModel
        self.lifecycleModel = lifecycleModel
        self.runModel = runModel
        self.buildModel = buildModel
        self.pluginCatalog = pluginCatalog
        self.actions = actions
        self.followLogs = followLogs
    }
}

/// Builds every command from the live context: 13 fixed actions, then dynamic Run/Build
/// presets, then discovered plugins. Selection-needing actions are disabled with a hint.
public enum CommandCatalog {
    @MainActor
    public static func actions(_ ctx: CommandContext) -> [CommandAction] {
        let shell = ctx.shell
        let hasImage = !ctx.imageBrowserModel.selection.isEmpty
        let hasContainer = !ctx.containerBrowserModel.selection.isEmpty
        let running = ctx.systemModel.health.isRunning

        var actions: [CommandAction] = [
            CommandAction(
                id: "run-selected-image", title: "Run Selected Image…",
                subtitle: hasImage ? nil : "Select an image first",
                symbol: "play.rectangle",
                shortcut: CommandShortcut("r", modifiers: [.shift, .command]),
                isEnabled: hasImage,
                run: {
                    let reference = ctx.imageBrowserModel.selectedImages.first?.reference
                    ctx.runModel.reset(image: reference ?? "")
                    shell.present(.run(imageReference: reference))
                }),
            CommandAction(
                id: "exec-shell", title: "Exec Shell in Container",
                subtitle: hasContainer ? nil : "Select a container first",
                symbol: "terminal", shortcut: nil, isEnabled: hasContainer,
                run: {
                    if let id = ctx.containerBrowserModel.selection.first {
                        ctx.lifecycleModel.openShell(id: id)
                    }
                }),
            CommandAction(
                id: "follow-logs", title: "Follow Logs", subtitle: nil,
                symbol: "text.alignleft", shortcut: nil, isEnabled: true,
                run: { ctx.followLogs() }),
            CommandAction(
                id: "build-folder", title: "Build from Folder…", subtitle: nil,
                symbol: "hammer",
                shortcut: CommandShortcut("b", modifiers: [.shift, .command]),
                isEnabled: true, run: { shell.present(.build) }),
            CommandAction(
                id: "pull-image", title: "Pull Image…", subtitle: nil,
                symbol: "arrow.down.circle",
                shortcut: CommandShortcut("p", modifiers: [.shift, .command]),
                isEnabled: true, run: { shell.present(.pull) }),
            CommandAction(
                id: "copy-to-container", title: "Copy File to Container…", subtitle: nil,
                symbol: "doc.on.doc", shortcut: nil, isEnabled: true,
                run: {
                    shell.present(.copy(containerID: ctx.containerBrowserModel.selection.first))
                }),
            CommandAction(
                id: "export-container", title: "Export Container…",
                subtitle: hasContainer ? nil : "Select a container first",
                symbol: "square.and.arrow.up", shortcut: nil, isEnabled: hasContainer,
                run: {
                    if let id = ctx.containerBrowserModel.selection.first {
                        shell.present(.export(containerID: id))
                    }
                }),
            CommandAction(
                id: "start-services", title: "Start Services", subtitle: nil,
                symbol: "play.fill", shortcut: nil, isEnabled: !running,
                run: { ctx.actions.recover(.startServices) }),
            CommandAction(
                id: "stop-services", title: "Stop Services", subtitle: nil,
                symbol: "stop.fill", shortcut: nil, isEnabled: running,
                run: { ctx.actions.stopServices() }),
            CommandAction(
                id: "open-system-logs", title: "Open System Logs", subtitle: nil,
                symbol: "doc.text.magnifyingglass", shortcut: nil, isEnabled: true,
                run: { shell.openSystem(tab: .serviceLogs) }),
            CommandAction(
                id: "reclaim-disk", title: "Reclaim Disk Space", subtitle: nil,
                symbol: "internaldrive", shortcut: nil, isEnabled: true,
                run: { shell.openSystem(tab: .storage) }),
            CommandAction(
                id: "toggle-inspector", title: "Toggle Inspector", subtitle: nil,
                symbol: "sidebar.right", shortcut: nil, isEnabled: true,
                run: { shell.toggleInspector() }),
            CommandAction(
                id: "raw-command-preview", title: "Open Raw Command Preview", subtitle: nil,
                symbol: "chevron.left.forwardslash.chevron.right",
                shortcut: CommandShortcut("k", modifiers: [.shift, .command]),
                isEnabled: true,
                run: {
                    // Best-fit seed computed LIVE at invocation (not a snapshot): the selected
                    // container's exec shell wins, else the selected image's run, else empty.
                    // Reads the context's live @Observable model references.
                    let seed: CommandInvocation? =
                        ctx.containerBrowserModel.selection.first
                        .map { ctx.lifecycleModel.execInvocation(id: $0) }
                        ?? ctx.imageBrowserModel.selectedImages.first
                        .map { ctx.runModel.runInvocation(forImage: $0.reference) }
                    shell.present(.console(seed: seed))
                }),
        ]

        for preset in ctx.runModel.runPresets {
            actions.append(
                CommandAction(
                    id: "preset-run-\(preset.id.uuidString)",
                    title: "Run Preset: \(preset.name)", subtitle: nil,
                    symbol: "play.rectangle.on.rectangle", shortcut: nil, isEnabled: true,
                    run: {
                        ctx.runModel.apply(preset)
                        shell.present(.run(imageReference: nil))
                    }))
        }
        for preset in ctx.buildModel.buildPresets {
            actions.append(
                CommandAction(
                    id: "preset-build-\(preset.id.uuidString)",
                    title: "Build Preset: \(preset.name)", subtitle: nil,
                    symbol: "hammer.circle", shortcut: nil, isEnabled: true,
                    run: {
                        ctx.buildModel.apply(preset)
                        shell.present(.build)
                    }))
        }
        for plugin in ctx.pluginCatalog.plugins {
            actions.append(
                CommandAction(
                    id: "plugin-\(plugin.name)", title: "Plugin: \(plugin.name)",
                    subtitle: plugin.path, symbol: "puzzlepiece.extension", shortcut: nil,
                    isEnabled: true,
                    run: { shell.openTerminal(ctx.pluginCatalog.terminalRequest(for: plugin)) }))
        }
        return actions
    }
}
