//
//  AppShellView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The navigational frame: a NavigationSplitView (sidebar | content) with a global health
//  banner pinned above the content, a trailing `.inspector`, and a persistent bottom
//  Activity pane. It binds only to domain models (`SystemStatusModel`, `WorkspaceModel`)
//  and the view-only `ShellState`.

import AppKit
import CapsuleDomain
import SwiftUI

public struct AppShellView: View {
    @Bindable var shell: ShellState
    let systemModel: SystemStatusModel
    let workspaceModel: WorkspaceModel
    @Bindable var browserModel: ContainerBrowserModel
    @Bindable var lifecycleModel: ContainerLifecycleModel
    let statsModel: ContainerStatsModel
    @Bindable var imageBrowserModel: ImageBrowserModel
    @Bindable var imageActionsModel: ImageActionsModel
    @Bindable var networkBrowserModel: NetworkBrowserModel
    @Bindable var networkActionsModel: NetworkActionsModel
    @Bindable var machineBrowserModel: MachineBrowserModel
    @Bindable var machineActionsModel: MachineActionsModel
    @Bindable var volumeBrowserModel: VolumeBrowserModel
    let volumeActionsModel: VolumeActionsModel
    @Bindable var taskCenter: TaskCenter
    @Bindable var storageModel: StorageDashboardModel
    @Bindable var serviceLogsModel: LogsModel
    @Bindable var aboutModel: AboutModel
    @Bindable var runModel: RunModel
    @Bindable var buildModel: BuildModel
    @Bindable var logsModel: LogsModel
    @Bindable var copyModel: CopyModel
    let actions: ShellActions
    let terminalSurfaceProvider: any TerminalSurfaceProviding
    let commandContext: CommandContext

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
        storageModel: StorageDashboardModel,
        serviceLogsModel: LogsModel,
        aboutModel: AboutModel,
        runModel: RunModel,
        buildModel: BuildModel,
        logsModel: LogsModel,
        copyModel: CopyModel,
        actions: ShellActions,
        terminalSurfaceProvider: any TerminalSurfaceProviding = StubTerminalSurfaceProvider(),
        commandContext: CommandContext
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
        self.storageModel = storageModel
        self.serviceLogsModel = serviceLogsModel
        self.aboutModel = aboutModel
        self.runModel = runModel
        self.buildModel = buildModel
        self.logsModel = logsModel
        self.copyModel = copyModel
        self.actions = actions
        self.terminalSurfaceProvider = terminalSurfaceProvider
        self.commandContext = commandContext
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(
                shell: shell,
                availableFeatures: systemModel.health.availableFeatures,
                bannerKind: systemModel.health.bannerKind,
                statusLabel: systemModel.health.statusLabel
            )
        } detail: {
            detailColumn
        }
        .task {
            await systemModel.refreshStatus()
            commandContext.pluginCatalog.refresh()
        }
        .sheet(isPresented: $shell.commandPalettePresented) {
            CommandPaletteView(shell: shell, context: commandContext)
        }
        .sheet(item: $shell.pendingSheet) { intent in
            pendingSheetView(intent)
        }
    }

    private var detailColumn: some View {
        VStack(spacing: 0) {
            SystemHealthBanner(
                health: systemModel.health,
                compatibilityWarning: systemModel.compatibilityWarning,
                onRecover: actions.recover
            )

            if let notice = lifecycleModel.notice {
                LifecycleNoticeView(
                    notice: notice,
                    onAction: { handleNoticeAction($0) },
                    onForceStop: { id in
                        lifecycleModel.notice = nil
                        // The real destructive escalation for a hung stop: kill (SIGKILL).
                        Task { _ = await lifecycleModel.kill(id: id) }
                    },
                    onDismiss: { lifecycleModel.notice = nil }
                )
                .padding(.top, 6)
            }

            if let notice = imageActionsModel.notice {
                LifecycleNoticeView(
                    notice: notice,
                    onAction: { _ in imageActionsModel.notice = nil },
                    onForceStop: { _ in imageActionsModel.notice = nil },
                    onDismiss: { imageActionsModel.notice = nil }
                )
                .padding(.top, 6)
            }

            if let notice = networkActionsModel.notice {
                LifecycleNoticeView(
                    notice: notice,
                    onAction: { _ in networkActionsModel.notice = nil },
                    onForceStop: { _ in networkActionsModel.notice = nil },
                    onDismiss: { networkActionsModel.notice = nil }
                )
                .padding(.top, 6)
            }

            if let notice = volumeActionsModel.notice {
                LifecycleNoticeView(
                    notice: notice,
                    onAction: { _ in volumeActionsModel.notice = nil },
                    onForceStop: { _ in volumeActionsModel.notice = nil },
                    onDismiss: { volumeActionsModel.notice = nil }
                )
                .padding(.top, 6)
            }

            if let notice = machineActionsModel.notice {
                LifecycleNoticeView(
                    notice: notice,
                    onAction: { _ in machineActionsModel.notice = nil },
                    onForceStop: { _ in machineActionsModel.notice = nil },
                    onDismiss: { machineActionsModel.notice = nil }
                )
                .padding(.top, 6)
            }

            ContentColumnView(
                section: shell.selection,
                systemTab: $shell.systemTab,
                health: systemModel.health,
                actions: actions,
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
                storageModel: storageModel,
                serviceLogsModel: serviceLogsModel,
                aboutModel: aboutModel,
                runModel: runModel,
                buildModel: buildModel,
                logsModel: logsModel,
                copyModel: copyModel
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if shell.activityPanePresented {
                ActivityPaneView(
                    shell: shell,
                    activityLog: shell.activityLog,
                    taskCenter: taskCenter,
                    attachSession: lifecycleModel.attachSession,
                    terminalAvailable: lifecycleModel.isTerminalAvailable,
                    terminalSurfaceProvider: terminalSurfaceProvider,
                    onDetach: { lifecycleModel.detach() },
                    onRetryAttach: { retryAttach() },
                    onOpenShell: { openShellForSelection() },
                    onCloseTerminal: { shell.closeTerminal() },
                    onOpenInTerminalApp: { request in
                        lifecycleModel.openInExternalTerminal(request.argv)
                    }
                )
            }
        }
        .inspector(isPresented: $shell.inspectorPresented) {
            Group {
                switch shell.selection {
                case .containers:
                    ContainerInspectorView(model: browserModel, stats: statsModel)
                case .images:
                    ImageInspectorView(model: imageBrowserModel)
                case .networks:
                    NetworkInspectorView(model: networkBrowserModel)
                case .volumes:
                    VolumeInspectorView(model: volumeBrowserModel)
                case .machines:
                    MachineInspectorView(model: machineBrowserModel, actions: machineActionsModel)
                default:
                    InspectorView(section: shell.selection)
                }
            }
            .inspectorColumnWidth(min: 240, ideal: 320, max: 420)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    shell.toggleActivityPane()
                } label: {
                    Image(systemName: "square.bottomthird.inset.filled")
                }
                .help("Toggle the Activity pane")

                Button {
                    shell.toggleInspector()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle the Inspector")
            }
        }
    }

    /// Routes a notice's recovery action. `.retry` is container-scoped — it refreshes the
    /// container list, never the system status. The `.retryInTerminal` case runs the command
    /// in the embedded terminal.
    private func handleNoticeAction(_ action: RecoveryAction) {
        switch action {
        case .retry:
            lifecycleModel.notice = nil
            Task { await browserModel.refresh() }
        case let .retryInTerminal(command):
            lifecycleModel.runInTerminal(command)
            lifecycleModel.notice = nil
        case .openLogs:
            shell.revealLogs()
            lifecycleModel.notice = nil
        default:
            actions.recover(action)
            lifecycleModel.notice = nil
        }
    }

    /// Re-attaches to the single selected container (the attach console's Retry button).
    private func retryAttach() {
        guard browserModel.selection.count == 1, let id = browserModel.selection.first else {
            return
        }
        lifecycleModel.retryAttach(id: id)
    }

    /// Opens a shell for the single selected container (the attach console's Open Shell).
    private func openShellForSelection() {
        guard browserModel.selection.count == 1, let id = browserModel.selection.first else {
            return
        }
        lifecycleModel.openShell(id: id)
    }

    /// Presents the app-level sheets requested from the palette/menus, reusing the same sheet
    /// views/models the list surfaces use. The caller (the catalog action) preps the model
    /// (e.g. `runModel.reset` / `runModel.apply`) before setting `shell.pendingSheet`.
    @ViewBuilder
    private func pendingSheetView(_ intent: AppSheetIntent) -> some View {
        switch intent {
        case .run:
            QuickRunSheet(
                model: runModel,
                onResolveImage: { _ in shell.present(.pull) },
                onClose: { shell.pendingSheet = nil })
        case .build:
            BuildSheet(model: buildModel, onClose: { shell.pendingSheet = nil })
        case .pull:
            PullImageSheet(
                initialReference: "",
                onPull: { reference, platform in
                    imageActionsModel.pull(reference: reference, platform: platform)
                },
                onRetry: { imageActionsModel.retryTask($0) },
                onClose: { shell.pendingSheet = nil },
                invocationFor: { ref, platform in
                    imageActionsModel.pullInvocation(reference: ref, platform: platform)
                })
        case let .copy(containerID):
            CopySheet(model: copyModel, onClose: { shell.pendingSheet = nil })
                .onAppear { copyModel.reset(containerID: containerID ?? "") }
        case let .export(containerID):
            exportSheet(containerID: containerID)
        case let .console(seed):
            CommandConsoleView(
                seed: seed,
                onRunEmbedded: { request in shell.openTerminal(request) },
                onRunExternal: { argv in lifecycleModel.openInExternalTerminal(argv) },
                onClose: { shell.pendingSheet = nil })
        }
    }

    /// A minimal export prompt: a Save panel feeds `lifecycleModel.export(id:to:)`.
    private func exportSheet(containerID: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Container").font(.headline)
            Text("Export “\(containerID)” to a tar archive on disk.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { shell.pendingSheet = nil }
                Button("Choose File…") {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "\(containerID).tar"
                    panel.canCreateDirectories = true
                    panel.title = "Export Container"
                    let response = panel.runModal()
                    shell.pendingSheet = nil
                    if response == .OK, let url = panel.url {
                        Task { await lifecycleModel.export(id: containerID, to: url) }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
