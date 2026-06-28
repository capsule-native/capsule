//
//  RootView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import SwiftUI

/// The top-level UI. It hosts the ``AppShellView`` and gates first-launch onboarding on an
/// `@AppStorage` flag.
///
/// It binds only to domain models (`SystemStatusModel`, `WorkspaceModel`) and the
/// view-only `ShellState`; it must never import a backend module (enforced by
/// `ArchitectureGuardTests` and `Scripts/check-architecture.sh`).
public struct RootView: View {
    private let shell: ShellState
    private let systemModel: SystemStatusModel
    private let workspaceModel: WorkspaceModel
    private let browserModel: ContainerBrowserModel
    private let lifecycleModel: ContainerLifecycleModel
    private let statsModel: ContainerStatsModel
    private let imageBrowserModel: ImageBrowserModel
    private let imageActionsModel: ImageActionsModel
    private let taskCenter: TaskCenter
    private let actions: ShellActions
    private let terminalSurfaceProvider: any TerminalSurfaceProviding

    @AppStorage("capsule.hasCompletedOnboarding") private var hasCompletedOnboarding = false

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
        self.terminalSurfaceProvider = terminalSurfaceProvider
    }

    public var body: some View {
        AppShellView(
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
            terminalSurfaceProvider: terminalSurfaceProvider
        )
        .sheet(isPresented: showOnboarding) {
            OnboardingView(health: systemModel.health, actions: actions) {
                hasCompletedOnboarding = true
            }
        }
    }

    private var showOnboarding: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding },
            set: { presenting in hasCompletedOnboarding = !presenting }
        )
    }
}
