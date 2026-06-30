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
    public var networkBrowserModel: NetworkBrowserModel
    public var networkActionsModel: NetworkActionsModel
    public var machineBrowserModel: MachineBrowserModel
    public var machineActionsModel: MachineActionsModel
    public var volumeBrowserModel: VolumeBrowserModel
    public var volumeActionsModel: VolumeActionsModel
    public var taskCenter: TaskCenter
    public var registriesModel: RegistriesModel
    public var dnsModel: DNSModel
    public var storageDashboardModel: StorageDashboardModel
    public var serviceLogsModel: LogsModel
    public var aboutModel: AboutModel
    public var runModel: RunModel
    public var buildModel: BuildModel
    public var logsModel: LogsModel
    public var copyModel: CopyModel
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
        networkBrowserModel: NetworkBrowserModel,
        networkActionsModel: NetworkActionsModel,
        machineBrowserModel: MachineBrowserModel,
        machineActionsModel: MachineActionsModel,
        volumeBrowserModel: VolumeBrowserModel,
        volumeActionsModel: VolumeActionsModel,
        taskCenter: TaskCenter,
        registriesModel: RegistriesModel,
        dnsModel: DNSModel,
        storageDashboardModel: StorageDashboardModel,
        serviceLogsModel: LogsModel,
        aboutModel: AboutModel,
        runModel: RunModel,
        buildModel: BuildModel,
        logsModel: LogsModel,
        copyModel: CopyModel,
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
        self.networkBrowserModel = networkBrowserModel
        self.networkActionsModel = networkActionsModel
        self.machineBrowserModel = machineBrowserModel
        self.machineActionsModel = machineActionsModel
        self.volumeBrowserModel = volumeBrowserModel
        self.volumeActionsModel = volumeActionsModel
        self.taskCenter = taskCenter
        self.registriesModel = registriesModel
        self.dnsModel = dnsModel
        self.storageDashboardModel = storageDashboardModel
        self.serviceLogsModel = serviceLogsModel
        self.aboutModel = aboutModel
        self.runModel = runModel
        self.buildModel = buildModel
        self.logsModel = logsModel
        self.copyModel = copyModel
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
        let networkBrowserModel = NetworkBrowserModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) }
        )
        let networkActionsModel = NetworkActionsModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            reloadList: { await networkBrowserModel.refresh() }
        )
        let volumeBrowserModel = VolumeBrowserModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) }
        )
        let volumeActionsModel = VolumeActionsModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            reloadList: { await volumeBrowserModel.refresh() }
        )
        let machineBrowserModel = MachineBrowserModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) }
        )
        let copyCommandToClipboard: @MainActor ([String]) -> Void = { argv in
            let command = argv.joined(separator: " ")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(command, forType: .string)
            shell.appendActivity("Copied to clipboard: \(command)")
        }
        let openInTerminalApp: @MainActor ([String]) -> Void = { argv in
            let app = currentTerminalApp()
            openCommandInTerminalApp(
                argv, executablePath: cliBackend.executableURL.path, terminalApp: app)
            shell.appendActivity("Opened in Terminal: \(argv.joined(separator: " "))")
        }
        let runPrivilegedInTerminal: @MainActor ([String]) -> Void = { argv in
            let app = currentTerminalApp()
            openPrivilegedCommandInTerminalApp(
                argv, executablePath: cliBackend.executableURL.path, terminalApp: app)
            shell.appendActivity("Opened in Terminal (sudo): \(argv.joined(separator: " "))")
        }
        let dnsModel = DNSModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            runPrivilegedInTerminal: runPrivilegedInTerminal
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
            copyCommand: copyCommandToClipboard,
            launchTerminal: { request in shell.openTerminal(request) },
            openExternalTerminal: openInTerminalApp,
            taskCenter: taskCenter
        )
        let machineActionsModel = MachineActionsModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            reloadList: { await machineBrowserModel.refresh() },
            currentState: { name in
                machineBrowserModel.allMachines.first { $0.name == name }?.state ?? .unknown
            },
            terminalAvailable: { true },
            copyCommand: copyCommandToClipboard,
            launchTerminal: { request in shell.openTerminal(request) },
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
        let storageDashboardModel = StorageDashboardModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onReclaim: { category in
                switch category {
                case .images: Task { _ = await imageActionsModel.prune(all: true) }
                case .containers: Task { _ = await lifecycleModel.prune() }
                case .volumes: Task { _ = await volumeActionsModel.prune() }
                }
            })
        let serviceLogsModel = LogsModel(source: .system(backend))
        let aboutModel = AboutModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString)
        let logsModel = LogsModel(backend: backend)
        let copyModel = CopyModel(
            backend: backend, taskCenter: taskCenter,
            onActivity: { line in shell.appendActivity(line) })
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
            networkBrowserModel: networkBrowserModel,
            networkActionsModel: networkActionsModel,
            machineBrowserModel: machineBrowserModel,
            machineActionsModel: machineActionsModel,
            volumeBrowserModel: volumeBrowserModel,
            volumeActionsModel: volumeActionsModel,
            taskCenter: taskCenter,
            registriesModel: registriesModel,
            dnsModel: dnsModel,
            storageDashboardModel: storageDashboardModel,
            serviceLogsModel: serviceLogsModel,
            aboutModel: aboutModel,
            runModel: runModel,
            buildModel: buildModel,
            logsModel: logsModel,
            copyModel: copyModel,
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
                case .grantPermission(.administrator):
                    // SAFETY NET ONLY. DNS create/delete already perform the privileged handoff
                    // directly from the per-row Add/Delete buttons in Settings > Networking
                    // (DNSModel builds the DNSConfiguration argv and calls
                    // runPrivilegedInTerminal). RecoveryAction.grantPermission carries no
                    // command, so we do NOT replay a specific argv here — there is no pending
                    // command. Point the user at the pane that does the privileged work.
                    shell.appendActivity(
                        "Administrator access is required. Open Settings > Networking to add or "
                            + "remove a DNS domain \u{2014} Capsule opens Terminal with sudo to finish it."
                    )
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

/// Writes `script` to a throwaway `.command` and opens it: with `terminalApp` when set
/// (falling back to the system `.command` handler if that open errors), else with the system
/// handler directly. Sweeps the temp file after 10s. Non-fatal on any failure.
// File-scope, NOT @MainActor — matches the existing `open*InTerminalApp` functions, which
// compile un-annotated in this module (Swift 5 concurrency mode). Do not add @MainActor.
private func openScriptInTerminal(_ script: String, terminalApp: URL?) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("capsule-\(UUID().uuidString).command")
    do {
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        if let terminalApp {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(
                [url], withApplicationAt: terminalApp, configuration: configuration
            ) {
                _, error in
                if error != nil {
                    // Chosen app couldn't open it — fall back to the default `.command` handler.
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            NSWorkspace.shared.open(url)
        }
        Task {
            try? await Task.sleep(for: .seconds(10))
            try? FileManager.default.removeItem(at: url)
        }
    } catch {
        // Non-fatal: the embedded terminal / manual run remains available.
    }
}

/// Reads the saved TerminalPreference and resolves it to an installed app URL (or nil for the
/// system default) at call time, so a settings change takes effect on the next handoff.
/// (File-scope, not @MainActor — matches the existing handoff functions in this module.)
private func currentTerminalApp() -> URL? {
    let raw = UserDefaults.standard.string(forKey: TerminalPreference.storageKey) ?? ""
    let preference = TerminalPreference(storage: raw) ?? .systemDefault
    return resolveTerminalApp(
        preference,
        lookup: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        fileExists: { FileManager.default.fileExists(atPath: $0) })
}

/// The detach fallback: write the argv to a temporary executable `.command` script and open
/// it, which launches it in Terminal.app. The `container` token is resolved to its absolute
/// path so the external shell can find it. Best-effort — a write/open failure is non-fatal.
func openCommandInTerminalApp(_ argv: [String], executablePath: String, terminalApp: URL?) {
    guard !argv.isEmpty else { return }
    let resolved = argv.enumerated().map { index, token in
        index == 0 && token == "container" ? executablePath : token
    }
    let command = resolved.map(shellQuote).joined(separator: " ")
    openScriptInTerminal("#!/bin/sh\nexec \(command)\n", terminalApp: terminalApp)
}

/// Pure helper: builds the `#!/bin/sh` script body for a privileged Terminal handoff.
/// The returned script uses `exec sudo <abs-executablePath> <shell-quoted argv>`. This
/// function is pure (no IO, no NSWorkspace) and is unit-testable independently of IO.
func privilegedTerminalScript(_ argv: [String], executablePath: String) -> String {
    let command = ([executablePath] + argv).map(shellQuote).joined(separator: " ")
    return "#!/bin/sh\nexec sudo \(command)\n"
}

/// The privileged variant of ``openCommandInTerminalApp``: writes a `.command` script whose
/// body is `exec sudo <container-path> <args…>`, so the user authenticates in Terminal and
/// the operation runs with administrator rights. The container executable is given as an
/// absolute path (the external shell has no Capsule context) and every token is shell-quoted.
/// Best-effort — a write/open failure is non-fatal.
func openPrivilegedCommandInTerminalApp(_ argv: [String], executablePath: String, terminalApp: URL?)
{
    guard !argv.isEmpty else { return }
    openScriptInTerminal(
        privilegedTerminalScript(argv, executablePath: executablePath), terminalApp: terminalApp)
}

/// Single-quotes a token for safe inclusion in a `/bin/sh` command line.
private func shellQuote(_ token: String) -> String {
    "'" + token.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
