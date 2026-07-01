//
//  SystemDetailView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The "System" section's content: a TabView with four tabs —
//  Overview (status + start/stop), Storage, Service Logs, and About/Diagnostics.

import CapsuleDomain
import SwiftUI

struct SystemDetailView: View {
    let health: SystemHealth
    let actions: ShellActions
    @Binding var selection: SystemTab
    let storageModel: StorageDashboardModel
    let serviceLogsModel: LogsModel
    let aboutModel: AboutModel

    var body: some View {
        TabView(selection: $selection) {
            overview
                .tabItem { Label("Overview", systemImage: "heart.text.square") }
                .tag(SystemTab.overview)
            StorageDashboardView(model: storageModel)
                .tabItem { Label("Storage", systemImage: "internaldrive") }
                .tag(SystemTab.storage)
            ServiceLogsView(model: serviceLogsModel, isRunning: health.isRunning)
                .tabItem { Label("Service Logs", systemImage: "doc.text.magnifyingglass") }
                .tag(SystemTab.serviceLogs)
            AboutDiagnosticsView(
                model: aboutModel,
                onExportDiagnostics: { actions.recover(.exportDiagnostics) }
            )
            .tabItem { Label("About", systemImage: "info.circle") }
            .tag(SystemTab.about)
        }
    }

    private var overview: some View {
        Form {
            Section("Status") {
                LabeledContent("Service") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(CapsuleColors.accent(for: health.bannerKind))
                            .frame(width: 8, height: 8)
                        Text(health.statusLabel)
                    }
                }
                if case let .running(version, _) = health {
                    LabeledContent("CLI", value: version.client)
                    LabeledContent("Service", value: version.server ?? "—")
                }
            }

            Section {
                HStack(spacing: 10) {
                    Button("Start Services") { actions.recover(.startServices) }
                        .buttonStyle(.borderedProminent)
                        .disabled(health.isRunning)
                    Button("Stop Services") { actions.stopServices() }
                        .buttonStyle(.bordered)
                        .disabled(!health.isRunning)
                    Spacer()
                    Button("Export Diagnostics…") { actions.recover(.exportDiagnostics) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
    }
}
