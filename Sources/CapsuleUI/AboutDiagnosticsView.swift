//
//  AboutDiagnosticsView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  About/diagnostics pane: component table, OS/app version, compatibility warnings,
//  Copy Bug Report (NSPasteboard), Export Diagnostics (injected onExportDiagnostics).

import CapsuleDomain
import SwiftUI

struct AboutDiagnosticsView: View {
    @Bindable var model: AboutModel
    let cliUpdate: ContainerCLIUpdateModel
    let onExportDiagnostics: () -> Void

    @State private var showUpdateSheet = false

    var body: some View {
        Group {
            if let err = model.loadFailed {
                ContentUnavailableView(
                    "Could not load components",
                    systemImage: "exclamationmark.circle",
                    description: Text(err)
                )
            } else {
                Form {
                    Section("Components") {
                        ForEach(model.components) { c in
                            LabeledContent(c.appName) {
                                VStack(alignment: .trailing) {
                                    Text(c.version).monospaced()
                                    Text("\(c.buildType) · \(c.commit)").font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Section("Container CLI") {
                        LabeledContent("Latest release") { latestLabel }
                        HStack {
                            Button("Update container…") { showUpdateSheet = true }
                                .accessibilityIdentifier("about-update-container-button")
                            Spacer()
                        }
                    }
                    if !model.compatibilityWarnings.isEmpty {
                        Section("Compatibility") {
                            ForEach(model.compatibilityWarnings, id: \.self) { w in
                                Label(w, systemImage: "exclamationmark.triangle").foregroundStyle(
                                    .orange)
                            }
                        }
                    }
                    Section {
                        HStack {
                            Button("Copy Bug Report") {
                                Pasteboard.copy(model.bugReportText)
                            }
                            Button("Export Diagnostics…", action: onExportDiagnostics)
                            Spacer()
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .task { await model.refresh() }
        .task { await cliUpdate.checkLatest() }
        .sheet(isPresented: $showUpdateSheet) {
            UpdateContainerSheet(
                scriptPreview: cliUpdate.updateScriptPreview,
                updaterScriptAvailable: cliUpdate.updaterScriptAvailable,
                onConfirm: { cliUpdate.runUpdater() })
        }
    }

    private var installedCLIVersion: String? {
        model.components.first { $0.appName == "container" }?.version
    }

    @ViewBuilder private var latestLabel: some View {
        switch cliUpdate.latest {
        case .idle, .checking:
            Text("Checking…").foregroundStyle(.secondary)
        case let .available(tag):
            HStack(spacing: 8) {
                Text(tag).monospaced()
                if ContainerCLIUpdateModel.isUpToDate(installed: installedCLIVersion, latest: tag) {
                    Text("Up to date").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Update available").font(.caption).foregroundStyle(.orange)
                }
            }
        case let .failed(message):
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }
}
