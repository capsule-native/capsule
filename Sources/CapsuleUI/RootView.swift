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
    private let actions: ShellActions

    @AppStorage("capsule.hasCompletedOnboarding") private var hasCompletedOnboarding = false

    public init(
        shell: ShellState,
        systemModel: SystemStatusModel,
        workspaceModel: WorkspaceModel,
        browserModel: ContainerBrowserModel,
        actions: ShellActions
    ) {
        self.shell = shell
        self.systemModel = systemModel
        self.workspaceModel = workspaceModel
        self.browserModel = browserModel
        self.actions = actions
    }

    public var body: some View {
        AppShellView(
            shell: shell,
            systemModel: systemModel,
            workspaceModel: workspaceModel,
            browserModel: browserModel,
            actions: actions
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
