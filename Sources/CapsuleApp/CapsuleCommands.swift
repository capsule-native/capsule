//
//  CapsuleCommands.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import CapsuleUI
import SwiftUI

/// Top-level menu commands.
///
/// The macOS menu bar is where users expect to find commands, so it is established early:
/// the standard App / File / Edit / Window / Help menus come from SwiftUI; this adds the
/// updater entry, **View** toggles for the inspector and Activity pane, and a **Resource**
/// menu (Refresh / Start / Stop Services) with a disabled Command Palette hook reserved
/// for Milestone 11. Commands operate on the shared models so the menu and the UI stay in
/// lockstep.
public struct CapsuleCommands: Commands {
    private let updater: any UpdaterController
    @Bindable private var shell: ShellState
    private let systemModel: SystemStatusModel
    private let actions: ShellActions
    private let machineActionsModel: MachineActionsModel
    private let commandContext: CommandContext
    @Environment(\.openWindow) private var openWindow

    public init(
        updater: any UpdaterController,
        shell: ShellState,
        systemModel: SystemStatusModel,
        actions: ShellActions,
        machineActionsModel: MachineActionsModel,
        commandContext: CommandContext
    ) {
        self.updater = updater
        self.shell = shell
        self.systemModel = systemModel
        self.actions = actions
        self.machineActionsModel = machineActionsModel
        self.commandContext = commandContext
    }

    public var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }

        // View — pane visibility.
        CommandGroup(after: .sidebar) {
            Button("Toggle Inspector") { shell.toggleInspector() }
                .keyboardShortcut("i", modifiers: [.option, .command])
            Button(shell.activityPanePresented ? "Hide Activity Pane" : "Show Activity Pane") {
                shell.toggleActivityPane()
            }
            .keyboardShortcut("j", modifiers: [.command])
            Button("Open Log Window") { openWindow(id: LogWindow.id) }
                .keyboardShortcut("l", modifiers: [.shift, .command])
        }

        // Machine — navigate to the Machines surface and open shells.
        CommandMenu("Machine") {
            Button("Create Machine\u{2026}") {
                // Navigates to the Machines surface so the user can press Create in the
                // toolbar. Opening the create sheet directly would require plumbing new
                // state through ShellState; the toolbar button is the canonical entry.
                shell.selection = .machines
            }
            .disabled(
                !SidebarSection.machines.isEnabled(features: systemModel.health.availableFeatures))

            Divider()

            Button("Open Machine Shell") {
                // Empty name → domain resolves to the default machine (machine run -it).
                machineActionsModel.openShell(name: "")
            }
            .disabled(
                !SidebarSection.machines.isEnabled(features: systemModel.health.availableFeatures))
        }

        // Resource — system lifecycle + a reserved command-palette hook (Milestone 11).
        CommandMenu("Resource") {
            Button("Refresh") {
                Task { await systemModel.refreshStatus() }
            }
            .keyboardShortcut("r", modifiers: [.command])

            Divider()

            Button("Start Services") { actions.recover(.startServices) }
                .disabled(systemModel.health.isRunning)
            Button("Stop Services") { actions.stopServices() }
                .disabled(!systemModel.health.isRunning)

            Divider()

            Button("Command Palette…") { shell.toggleCommandPalette() }
                .keyboardShortcut("k", modifiers: [.command])
        }

        // Commands — every fixed catalog action, rendered from the same source the palette uses.
        CommandMenu("Commands") {
            ForEach(fixedActions) { menuButton($0) }
        }

        // Presets — dynamic Run/Build presets and discovered plugins.
        CommandMenu("Presets") {
            if dynamicActions.isEmpty {
                Button("No Presets or Plugins") {}.disabled(true)
            } else {
                ForEach(dynamicActions) { menuButton($0) }
            }
        }
    }

    @MainActor
    private var catalogActions: [CommandAction] { CommandCatalog.actions(commandContext) }

    @MainActor
    private var fixedActions: [CommandAction] {
        catalogActions.filter { !$0.id.hasPrefix("preset-") && !$0.id.hasPrefix("plugin-") }
    }

    @MainActor
    private var dynamicActions: [CommandAction] {
        catalogActions.filter { $0.id.hasPrefix("preset-") || $0.id.hasPrefix("plugin-") }
    }

    @ViewBuilder
    private func menuButton(_ action: CommandAction) -> some View {
        let button = Button(action.title) { action.run() }
            .disabled(!action.isEnabled)
        if let shortcut = action.shortcut {
            button.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            button
        }
    }
}
