//
//  AdvancedSettingsView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Advanced tab in Preferences. Hosts the Kernel section now; Task 18 adds the
//  Configuration section.

import CapsuleDomain
import SwiftUI

struct AdvancedSettingsView: View {
    @Bindable var kernelModel: KernelManagerModel
    // Task 18 adds: let propertiesModel: SystemPropertiesModel
    @State private var showingKernelSheet = false

    var body: some View {
        Form {
            Section("Kernel") {
                LabeledContent("Current kernel", value: kernelModel.currentKernelSummary ?? "—")
                Button("Change Kernel…") { showingKernelSheet = true }
            }
            // Task 18 inserts the Configuration section here.
        }
        .formStyle(.grouped)
        .task { await kernelModel.loadCurrent() }
        .sheet(isPresented: $showingKernelSheet) {
            KernelSetupSheet(model: kernelModel)
        }
    }
}
