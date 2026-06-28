//
//  CapsuleScene.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import CapsuleUI
import SwiftUI

/// The application's root `Scene`.
///
/// The Xcode app target's tiny `@main` shim renders this; all real lifecycle, command,
/// and composition logic lives in this module so it stays testable and out of the
/// app-bundle target.
@MainActor
public struct CapsuleScene: Scene {
    @State private var shell: ShellState
    @State private var systemModel: SystemStatusModel
    @State private var workspaceModel: WorkspaceModel
    @State private var browserModel: ContainerBrowserModel
    @State private var lifecycleModel: ContainerLifecycleModel
    @State private var statsModel: ContainerStatsModel
    private let actions: ShellActions
    private let updater: any UpdaterController
    private let terminalSurfaceProvider: any TerminalSurfaceProviding

    public init() {
        self.init(environment: .live())
    }

    public init(environment: AppEnvironment) {
        self._shell = State(initialValue: environment.shell)
        self._systemModel = State(initialValue: environment.systemModel)
        self._workspaceModel = State(initialValue: environment.workspaceModel)
        self._browserModel = State(initialValue: environment.browserModel)
        self._lifecycleModel = State(initialValue: environment.lifecycleModel)
        self._statsModel = State(initialValue: environment.statsModel)
        self.actions = environment.actions
        self.updater = environment.updater
        self.terminalSurfaceProvider = environment.terminalSurfaceProvider
    }

    public var body: some Scene {
        WindowGroup(id: WindowManagement.mainWindowID) {
            RootView(
                shell: shell,
                systemModel: systemModel,
                workspaceModel: workspaceModel,
                browserModel: browserModel,
                lifecycleModel: lifecycleModel,
                statsModel: statsModel,
                actions: actions,
                terminalSurfaceProvider: terminalSurfaceProvider
            )
        }
        .commands {
            CapsuleCommands(
                updater: updater,
                shell: shell,
                systemModel: systemModel,
                actions: actions
            )
        }
    }
}
