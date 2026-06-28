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
    @Bindable var taskCenter: TaskCenter
    @Bindable var runModel: RunModel
    let actions: ShellActions
    let terminalSurfaceProvider: any TerminalSurfaceProviding

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
        runModel: RunModel,
        actions: ShellActions,
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
        self.runModel = runModel
        self.actions = actions
        self.terminalSurfaceProvider = terminalSurfaceProvider
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

            ContentColumnView(
                section: shell.selection,
                health: systemModel.health,
                actions: actions,
                browserModel: browserModel,
                lifecycleModel: lifecycleModel,
                statsModel: statsModel,
                imageBrowserModel: imageBrowserModel,
                imageActionsModel: imageActionsModel,
                runModel: runModel
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
                    onCloseTerminal: { shell.closeTerminal() }
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
}
