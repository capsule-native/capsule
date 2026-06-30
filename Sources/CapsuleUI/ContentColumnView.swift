//
//  ContentColumnView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The middle column of the split view. It is health-gated on purpose: when the service
//  is not running it shows an explicit health/error state with recovery actions — never an
//  empty list, because "no data" must not be mistaken for "nothing to manage".

import CapsuleDomain
import SwiftUI

struct ContentColumnView: View {
    let section: SidebarSection
    let health: SystemHealth
    let actions: ShellActions
    let browserModel: ContainerBrowserModel
    let lifecycleModel: ContainerLifecycleModel
    let statsModel: ContainerStatsModel
    let imageBrowserModel: ImageBrowserModel
    let imageActionsModel: ImageActionsModel
    let networkBrowserModel: NetworkBrowserModel
    let networkActionsModel: NetworkActionsModel
    let machineBrowserModel: MachineBrowserModel
    let machineActionsModel: MachineActionsModel
    let volumeBrowserModel: VolumeBrowserModel
    let volumeActionsModel: VolumeActionsModel
    let storageModel: StorageDashboardModel
    let serviceLogsModel: LogsModel
    let aboutModel: AboutModel
    let runModel: RunModel
    let buildModel: BuildModel
    let logsModel: LogsModel
    let copyModel: CopyModel

    private var onRecover: (RecoveryAction) -> Void { actions.recover }

    var body: some View {
        Group {
            if section == .system {
                SystemDetailView(
                    health: health, actions: actions,
                    storageModel: storageModel,
                    serviceLogsModel: serviceLogsModel,
                    aboutModel: aboutModel)
            } else if health.isRunning {
                if isGatedSurfaceUnavailable {
                    unsupportedSurface
                } else {
                    runningContent
                }
            } else {
                healthState
            }
        }
        .navigationTitle(section.title)
    }

    /// The content shown for a running service. Containers get the live browser; other
    /// sections keep the friendly placeholder until their milestones land.
    @ViewBuilder
    private var runningContent: some View {
        switch section {
        case .containers:
            ContainerListView(
                model: browserModel, lifecycle: lifecycleModel, stats: statsModel,
                logsModel: logsModel, copyModel: copyModel)
        case .images:
            ImageListView(
                model: imageBrowserModel, actions: imageActionsModel, runModel: runModel,
                buildModel: buildModel)
        case .volumes:
            VolumeListView(model: volumeBrowserModel, actions: volumeActionsModel)
        case .networks:
            NetworkListView(model: networkBrowserModel, actions: networkActionsModel)
        case .machines:
            MachineListView(model: machineBrowserModel, actions: machineActionsModel)
        default:
            resourcePlaceholder
        }
    }

    /// Until real lists land (later milestones), a running service shows a friendly
    /// "nothing here yet" rather than a blank pane.
    private var resourcePlaceholder: some View {
        ContentUnavailableView {
            Label(section.title, systemImage: section.symbolName)
        } description: {
            Text("\(section.title) will appear here.")
        }
    }

    /// True only for a running service whose build does not report the family of a *gated*
    /// resource surface (volumes / networks / machines). Containers / images keep their own
    /// routing untouched — capability gating scopes itself to these gated surfaces, so the
    /// `runningContent` switch is left intact and the gate composes additively around its
    /// dispatch.
    private var isGatedSurfaceUnavailable: Bool {
        switch section {
        case .volumes, .networks, .machines:
            return !section.isEnabled(features: health.availableFeatures)
        default:
            return false
        }
    }

    /// Shown when the service is running but this build does not report the section's family
    /// (e.g. an OS / container build without `volumes` or `networks`). The whole surface —
    /// list, Create…, Delete, Clean Up — is withheld rather than erroring on use, satisfying
    /// the acceptance rule that unsupported families are hidden, not errored.
    private var unsupportedSurface: some View {
        ContentUnavailableView {
            Label("\(section.title) unavailable", systemImage: "exclamationmark.octagon")
        } description: {
            Text("\(section.title) are not supported by the current container build.")
        }
    }

    /// The health/error state shown whenever the service is not running.
    @ViewBuilder
    private var healthState: some View {
        let text = SystemHealthBanner.bannerText(for: health, warning: nil)
        let actions = SystemHealthBanner.recoveryActions(for: health)

        ContentUnavailableView {
            Label(text.title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(text.message)
        } actions: {
            if !actions.isEmpty {
                RecoveryActionButtons(actions: actions, onRecover: onRecover)
            }
        }
    }
}
