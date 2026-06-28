//
//  AppEnvironment.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import AppKit
import CapsuleBackend
import CapsuleCLIBackend
import CapsuleDiagnostics
import CapsuleDomain
import CapsuleUI
import Foundation

/// The composition root.
///
/// This is the single place that knows about concrete adapters and wires them into the
/// domain and UI. It also injects the cross-layer seams the lower layers cannot reach on
/// their own — notably `ErrorNormalizer.normalize` (which lives in `CapsuleDiagnostics`,
/// a module the domain must not import) — and builds the `ShellActions` that route UI
/// recovery actions back to the models.
@MainActor
public struct AppEnvironment {
    public var shell: ShellState
    public var systemModel: SystemStatusModel
    public var workspaceModel: WorkspaceModel
    public var browserModel: ContainerBrowserModel
    public var lifecycleModel: ContainerLifecycleModel
    public var statsModel: ContainerStatsModel
    public var actions: ShellActions
    public var updater: any UpdaterController

    public init(
        shell: ShellState,
        systemModel: SystemStatusModel,
        workspaceModel: WorkspaceModel,
        browserModel: ContainerBrowserModel,
        lifecycleModel: ContainerLifecycleModel,
        statsModel: ContainerStatsModel,
        actions: ShellActions,
        updater: any UpdaterController
    ) {
        self.shell = shell
        self.systemModel = systemModel
        self.workspaceModel = workspaceModel
        self.browserModel = browserModel
        self.lifecycleModel = lifecycleModel
        self.statsModel = statsModel
        self.actions = actions
        self.updater = updater
    }

    /// The production environment: CLI backend, normalized errors, and a wired shell.
    public static func live() -> AppEnvironment {
        let backend: any ContainerBackend = CLIContainerBackend()
        let shell = ShellState()
        let systemModel = SystemStatusModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) }
        )
        let workspaceModel = WorkspaceModel(backend: backend)
        let browserModel = ContainerBrowserModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            scopeStore: UserDefaultsScopeStore(),
            onActivity: { line in shell.appendActivity(line) }
        )
        let statsModel = ContainerStatsModel(backend: backend)
        let lifecycleModel = ContainerLifecycleModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            reloadList: { await browserModel.refresh() },
            currentState: { id in
                browserModel.allContainers.first { $0.id == id }?.state ?? .unknown
            },
            terminalAvailable: { false },
            copyCommand: { argv in
                let command = argv.joined(separator: " ")
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(command, forType: .string)
                shell.appendActivity("Copied to clipboard: \(command)")
            }
        )
        let actions = makeActions(systemModel: systemModel, shell: shell)
        return AppEnvironment(
            shell: shell,
            systemModel: systemModel,
            workspaceModel: workspaceModel,
            browserModel: browserModel,
            lifecycleModel: lifecycleModel,
            statsModel: statsModel,
            actions: actions,
            updater: NoopUpdaterController()
        )
    }

    /// Builds the recovery/stop callbacks that bridge UI actions to the system model.
    static func makeActions(
        systemModel: SystemStatusModel,
        shell: ShellState
    ) -> ShellActions {
        ShellActions(
            recover: { action in
                switch action {
                case .startServices:
                    Task { await systemModel.startServices() }
                case .retry:
                    Task { await systemModel.refreshStatus() }
                case .openLogs:
                    shell.revealLogs()
                case .exportDiagnostics:
                    shell.appendActivity("Diagnostics export requested.")
                case .retryInTerminal, .editConfiguration, .grantPermission:
                    shell.appendActivity("Action “\(action.title)” is not available yet.")
                }
            },
            stopServices: {
                Task { await systemModel.stopServices() }
            }
        )
    }
}
