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
    let actions: ShellActions

    public init(
        shell: ShellState,
        systemModel: SystemStatusModel,
        workspaceModel: WorkspaceModel,
        actions: ShellActions
    ) {
        self.shell = shell
        self.systemModel = systemModel
        self.workspaceModel = workspaceModel
        self.actions = actions
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

            ContentColumnView(
                section: shell.selection,
                health: systemModel.health,
                actions: actions
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if shell.activityPanePresented {
                ActivityPaneView(shell: shell, activityLog: shell.activityLog)
            }
        }
        .inspector(isPresented: $shell.inspectorPresented) {
            InspectorView(section: shell.selection)
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
}
