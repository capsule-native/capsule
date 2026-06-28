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

    private var onRecover: (RecoveryAction) -> Void { actions.recover }

    var body: some View {
        Group {
            if section == .system {
                SystemDetailView(health: health, actions: actions)
            } else if health.isRunning {
                runningContent
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
            ContainerListView(model: browserModel, lifecycle: lifecycleModel, stats: statsModel)
        case .images:
            ImageListView(model: imageBrowserModel)
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
