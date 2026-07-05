//
//  CapsuleMenuBar.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The menu attached to Capsule's status-bar item. Because the app stays resident after its
//  window closes (see `CapsuleAppDelegate`), this menu is the always-available way back in:
//  reopen the window, glance at the running containers, watch / toggle the runtime, reach
//  Settings and updates, or quit for real. It lives in `CapsuleApp` — like `CapsuleCommands`
//  — because it drives app-lifecycle concerns (`openWindow`, `NSApp`) and the composition
//  root's models, which the layered UI module must not own.

import AppKit
import CapsuleDomain
import CapsuleUI
import SwiftUI

/// The contents of Capsule's `MenuBarExtra`. Intentionally minimal: a way back to the window,
/// the currently running containers, the runtime's status with a start/stop toggle, Settings,
/// updates, and Quit.
struct CapsuleMenuBarContent: View {
    let shell: ShellState
    let browserModel: ContainerBrowserModel
    let systemModel: SystemStatusModel
    let actions: ShellActions
    let updater: any UpdaterController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open Capsule") { openMainWindow() }

        Divider()

        Section("Running Containers") {
            if runningContainers.isEmpty {
                Text("No Running Containers")
            } else {
                ForEach(runningContainers) { container in
                    Button(container.name) { reveal(container) }
                }
            }
        }

        Divider()

        // Disabled row: a live glance at whether the container runtime is up.
        Text("Services: \(String(localized: systemModel.health.localizedStatusLabel))")
        Button("Start Services") { actions.recover(.startServices) }
            .disabled(systemModel.health.isRunning)
        Button("Stop Services") { actions.stopServices() }
            .disabled(!systemModel.health.isRunning)

        Divider()

        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)

        Divider()

        Button("Quit Capsule") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// The running containers, name-sorted — independent of whatever search/filter the window
    /// happens to have applied (this reads `allContainers`, not the filtered `rows`).
    private var runningContainers: [Container] {
        browserModel.allContainers
            .filter { $0.state == .running }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Brings the window forward and reveals the given container in the Containers surface.
    private func reveal(_ container: Container) {
        openMainWindow()
        shell.selection = .containers
        browserModel.selection = [container.id]
    }

    /// Brings the main window back (re-creating it if it was closed) and pulls Capsule to the
    /// front — a status-item click does not activate the owning app on its own.
    private func openMainWindow() {
        openWindow(id: WindowManagement.mainWindowID)
        NSApp.activate()
    }
}
