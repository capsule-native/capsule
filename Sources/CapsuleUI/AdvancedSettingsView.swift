//
//  AdvancedSettingsView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Advanced tab in Preferences. Hosts the Kernel section and the Configuration section
//  (TOML viewer/editor via PropertiesEditorSheet).

import CapsuleDomain
import SwiftUI

struct AdvancedSettingsView: View {
    @Bindable var kernelModel: KernelManagerModel
    @Bindable var propertiesModel: SystemPropertiesModel
    @State private var showingKernelSheet = false
    @State private var showingEditor = false

    var body: some View {
        Form {
            Section("Kernel") {
                LabeledContent("Current kernel", value: kernelModel.currentKernelSummary ?? "—")
                Button("Change Kernel…") { showingKernelSheet = true }
            }
            Section("Configuration") {
                if let err = propertiesModel.loadError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                if propertiesModel.requiresRestart {
                    Label(
                        propertiesModel.restartBannerMessage,
                        systemImage: "arrow.clockwise.circle"
                    ).foregroundStyle(.orange)
                }
                ForEach(propertiesModel.sections) { s in
                    LabeledContent(s.name, value: "\(s.entries.count) keys")
                }
                Button("Edit Configuration…") { showingEditor = true }
            }
        }
        .formStyle(.grouped)
        .task { await kernelModel.loadCurrent() }
        .task { await propertiesModel.load() }
        .sheet(isPresented: $showingKernelSheet) {
            KernelSetupSheet(model: kernelModel)
        }
        .sheet(isPresented: $showingEditor) {
            PropertiesEditorSheet(model: propertiesModel)
        }
    }
}
