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
    public var registriesModel: RegistriesModel
    public var runModel: RunModel
    public var buildModel: BuildModel
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
        registriesModel: RegistriesModel,
        runModel: RunModel,
        buildModel: BuildModel,
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
        self.registriesModel = registriesModel
        self.runModel = runModel
        self.buildModel = buildModel
        self.actions = actions
        self.updater = updater
        self.terminalSurfaceProvider = terminalSurfaceProvider
    }

    /// The production environment: CLI backend, normalized errors, and a wired shell.
    public static func live() -> AppEnvironment {
        let cliBackend = CLIContainerBackend()
        let backend: any ContainerBackend = cliBackend
        let shell = ShellState()
        let taskCenter = TaskCenter(normalize: { ErrorNormalizer.normalize($0) })
        let systemModel = SystemStatusModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            taskCenter: taskCenter
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
        let registriesModel = RegistriesModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) }
        )
        let imageActionsModel = ImageActionsModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            reloadList: { await imageBrowserModel.refresh() },
            taskCenter: taskCenter
        )
        let copyCommandToClipboard: @MainActor ([String]) -> Void = { argv in
            let command = argv.joined(separator: " ")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(command, forType: .string)
            shell.appendActivity("Copied to clipboard: \(command)")
        }
        let openInTerminalApp: @MainActor ([String]) -> Void = { argv in
            openCommandInTerminalApp(argv, executablePath: cliBackend.executableURL.path)
            shell.appendActivity("Opened in Terminal: \(argv.joined(separator: " "))")
        }
        let lifecycleModel = ContainerLifecycleModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            reloadList: { await browserModel.refresh() },
            currentState: { id in
                browserModel.allContainers.first { $0.id == id }?.state ?? .unknown
            },
            terminalAvailable: { true },
            copyCommand: copyCommandToClipboard,
            launchTerminal: { request in shell.openTerminal(request) },
            openExternalTerminal: openInTerminalApp,
            taskCenter: taskCenter
        )
        let runModel = RunModel(
            backend: backend,
            taskCenter: taskCenter,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            reloadList: { await browserModel.refresh() },
            terminalAvailable: { true },
            launchTerminal: { request in shell.openTerminal(request) },
            copyCommand: copyCommandToClipboard
        )
        let buildModel = BuildModel(
            backend: backend,
            taskCenter: taskCenter,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            reloadList: { await imageBrowserModel.refresh() }
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
            registriesModel: registriesModel,
            runModel: runModel,
            buildModel: buildModel,
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

/// The detach fallback: write the argv to a temporary executable `.command` script and open
/// it, which launches it in Terminal.app. The `container` token is resolved to its absolute
/// path so the external shell can find it. Best-effort — a write/open failure is non-fatal.
@MainActor
func openCommandInTerminalApp(_ argv: [String], executablePath: String) {
    guard !argv.isEmpty else { return }
    let resolved = argv.enumerated().map { index, token in
        index == 0 && token == "container" ? executablePath : token
    }
    let command = resolved.map(shellQuote).joined(separator: " ")
    let script = "#!/bin/sh\nexec \(command)\n"
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("capsule-\(UUID().uuidString).command")
    do {
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
    } catch {
        // Non-fatal: the embedded terminal remains available.
    }
}

/// Single-quotes a token for safe inclusion in a `/bin/sh` command line.
private func shellQuote(_ token: String) -> String {
    "'" + token.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
