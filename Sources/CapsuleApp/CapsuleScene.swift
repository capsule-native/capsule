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
    @State private var imageBrowserModel: ImageBrowserModel
    @State private var imageActionsModel: ImageActionsModel
    @State private var networkBrowserModel: NetworkBrowserModel
    @State private var networkActionsModel: NetworkActionsModel
    @State private var machineBrowserModel: MachineBrowserModel
    @State private var machineActionsModel: MachineActionsModel
    @State private var volumeBrowserModel: VolumeBrowserModel
    @State private var volumeActionsModel: VolumeActionsModel
    @State private var taskCenter: TaskCenter
    @State private var registriesModel: RegistriesModel
    @State private var dnsModel: DNSModel
    @State private var kernelManagerModel: KernelManagerModel
    @State private var storageDashboardModel: StorageDashboardModel
    @State private var serviceLogsModel: LogsModel
    @State private var aboutModel: AboutModel
    @State private var runModel: RunModel
    @State private var buildModel: BuildModel
    @State private var logsModel: LogsModel
    @State private var copyModel: CopyModel
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
        self._imageBrowserModel = State(initialValue: environment.imageBrowserModel)
        self._imageActionsModel = State(initialValue: environment.imageActionsModel)
        self._networkBrowserModel = State(initialValue: environment.networkBrowserModel)
        self._networkActionsModel = State(initialValue: environment.networkActionsModel)
        self._machineBrowserModel = State(initialValue: environment.machineBrowserModel)
        self._machineActionsModel = State(initialValue: environment.machineActionsModel)
        self._volumeBrowserModel = State(initialValue: environment.volumeBrowserModel)
        self._volumeActionsModel = State(initialValue: environment.volumeActionsModel)
        self._taskCenter = State(initialValue: environment.taskCenter)
        self._registriesModel = State(initialValue: environment.registriesModel)
        self._dnsModel = State(initialValue: environment.dnsModel)
        self._kernelManagerModel = State(initialValue: environment.kernelManagerModel)
        self._storageDashboardModel = State(initialValue: environment.storageDashboardModel)
        self._serviceLogsModel = State(initialValue: environment.serviceLogsModel)
        self._aboutModel = State(initialValue: environment.aboutModel)
        self._runModel = State(initialValue: environment.runModel)
        self._buildModel = State(initialValue: environment.buildModel)
        self._logsModel = State(initialValue: environment.logsModel)
        self._copyModel = State(initialValue: environment.copyModel)
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
                imageBrowserModel: imageBrowserModel,
                imageActionsModel: imageActionsModel,
                networkBrowserModel: networkBrowserModel,
                networkActionsModel: networkActionsModel,
                machineBrowserModel: machineBrowserModel,
                machineActionsModel: machineActionsModel,
                volumeBrowserModel: volumeBrowserModel,
                volumeActionsModel: volumeActionsModel,
                taskCenter: taskCenter,
                storageModel: storageDashboardModel,
                serviceLogsModel: serviceLogsModel,
                aboutModel: aboutModel,
                runModel: runModel,
                buildModel: buildModel,
                logsModel: logsModel,
                copyModel: copyModel,
                actions: actions,
                terminalSurfaceProvider: terminalSurfaceProvider
            )
        }
        .commands {
            CapsuleCommands(
                updater: updater,
                shell: shell,
                systemModel: systemModel,
                actions: actions,
                machineActionsModel: machineActionsModel
            )
        }

        Window("Logs", id: LogWindow.id) {
            LogWindowView(model: logsModel)
        }

        Settings {
            PreferencesView(
                registriesModel: registriesModel,
                dnsModel: dnsModel,
                kernelModel: kernelManagerModel,
                systemHealth: systemModel.health)
        }
    }
}
