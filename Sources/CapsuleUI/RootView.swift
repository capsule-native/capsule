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
    private let registrySearchModel: RegistrySearchModel
    private let networkBrowserModel: NetworkBrowserModel
    private let networkActionsModel: NetworkActionsModel
    private let machineBrowserModel: MachineBrowserModel
    private let machineActionsModel: MachineActionsModel
    private let volumeBrowserModel: VolumeBrowserModel
    private let volumeActionsModel: VolumeActionsModel
    private let taskCenter: TaskCenter
    private let storageModel: StorageDashboardModel
    private let serviceLogsModel: LogsModel
    private let aboutModel: AboutModel
    private let runModel: RunModel
    private let buildModel: BuildModel
    private let logsModel: LogsModel
    private let copyModel: CopyModel
    private let actions: ShellActions
    private let terminalSurfaceProvider: any TerminalSurfaceProviding
    private let commandContext: CommandContext

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
        registrySearchModel: RegistrySearchModel,
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
        self.registrySearchModel = registrySearchModel
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
        AppShellView(
            shell: shell,
            systemModel: systemModel,
            workspaceModel: workspaceModel,
            browserModel: browserModel,
            lifecycleModel: lifecycleModel,
            statsModel: statsModel,
            imageBrowserModel: imageBrowserModel,
            imageActionsModel: imageActionsModel,
            registrySearchModel: registrySearchModel,
            networkBrowserModel: networkBrowserModel,
            networkActionsModel: networkActionsModel,
            machineBrowserModel: machineBrowserModel,
            machineActionsModel: machineActionsModel,
            volumeBrowserModel: volumeBrowserModel,
            volumeActionsModel: volumeActionsModel,
            taskCenter: taskCenter,
            storageModel: storageModel,
            serviceLogsModel: serviceLogsModel,
            aboutModel: aboutModel,
            runModel: runModel,
            buildModel: buildModel,
            logsModel: logsModel,
            copyModel: copyModel,
            actions: actions,
            terminalSurfaceProvider: terminalSurfaceProvider,
            commandContext: commandContext
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
