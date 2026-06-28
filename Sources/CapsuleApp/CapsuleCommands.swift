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
    @Environment(\.openWindow) private var openWindow

    public init(
        updater: any UpdaterController,
        shell: ShellState,
        systemModel: SystemStatusModel,
        actions: ShellActions
    ) {
        self.updater = updater
        self.shell = shell
        self.systemModel = systemModel
        self.actions = actions
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

            Button("Command Palette…") {}
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(true)
        }
    }
}
