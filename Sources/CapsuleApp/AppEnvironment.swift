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
import CapsuleTerminal
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
    public var imageBrowserModel: ImageBrowserModel
    public var imageActionsModel: ImageActionsModel
    public var taskCenter: TaskCenter
    public var actions: ShellActions
    public var updater: any UpdaterController
    public var terminalSurfaceProvider: any TerminalSurfaceProviding

    public init(
        shell: ShellState,
        systemModel: SystemStatusModel,
        workspaceModel: WorkspaceModel,
        browserModel: ContainerBrowserModel,
        lifecycleModel: ContainerLifecycleModel,
        statsModel: ContainerStatsModel,
        imageBrowserModel: ImageBrowserModel,
        imageActionsModel: ImageActionsModel,
        taskCenter: TaskCenter,
        actions: ShellActions,
        updater: any UpdaterController,
        terminalSurfaceProvider: any TerminalSurfaceProviding = StubTerminalSurfaceProvider()
    ) {
        self.shell = shell
        self.systemModel = systemModel
        self.workspaceModel = workspaceModel
        self.browserModel = browserModel
        self.lifecycleModel = lifecycleModel
        self.statsModel = statsModel
        self.imageBrowserModel = imageBrowserModel
        self.imageActionsModel = imageActionsModel
        self.taskCenter = taskCenter
        self.actions = actions
        self.updater = updater
        self.terminalSurfaceProvider = terminalSurfaceProvider
    }

    /// The production environment: CLI backend, normalized errors, and a wired shell.
    public static func live() -> AppEnvironment {
        let cliBackend = CLIContainerBackend()
        let backend: any ContainerBackend = cliBackend
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
        let imageBrowserModel = ImageBrowserModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) }
        )
        let taskCenter = TaskCenter(normalize: { ErrorNormalizer.normalize($0) })
        let imageActionsModel = ImageActionsModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            reloadList: { await imageBrowserModel.refresh() },
            taskCenter: taskCenter
        )
        let lifecycleModel = ContainerLifecycleModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            reloadList: { await browserModel.refresh() },
            currentState: { id in
                browserModel.allContainers.first { $0.id == id }?.state ?? .unknown
            },
            terminalAvailable: { true },
            copyCommand: { argv in
                let command = argv.joined(separator: " ")
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(command, forType: .string)
                shell.appendActivity("Copied to clipboard: \(command)")
            },
            launchTerminal: { request in shell.openTerminal(request) }
        )
        let terminalSurfaceProvider = SwiftTermSurfaceProvider(executablePath: { name in
            name == "container" ? cliBackend.executableURL.path : name
        })
        let actions = makeActions(systemModel: systemModel, shell: shell)
        return AppEnvironment(
            shell: shell,
            systemModel: systemModel,
            workspaceModel: workspaceModel,
            browserModel: browserModel,
            lifecycleModel: lifecycleModel,
            statsModel: statsModel,
            imageBrowserModel: imageBrowserModel,
            imageActionsModel: imageActionsModel,
            taskCenter: taskCenter,
            actions: actions,
            updater: NoopUpdaterController(),
            terminalSurfaceProvider: terminalSurfaceProvider
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
                case let .retryInTerminal(command):
                    shell.openTerminal(
                        TerminalRequest(
                            containerID: nil, title: "Terminal", argv: command, kind: .retry))
                case .editConfiguration, .grantPermission:
                    shell.appendActivity("Action “\(action.title)” is not available yet.")
                }
            },
            stopServices: {
                Task { await systemModel.stopServices() }
            }
        )
    }
}
