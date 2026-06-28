//
//  InspectorView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import SwiftUI

/// The trailing inspector. A placeholder until per-resource inspectors land; it already
/// participates in the `.inspector` column so toggling and resizing work today.
struct InspectorView: View {
    let section: SidebarSection

    var body: some View {
        Form {
            Section("Inspector") {
                LabeledContent("Section", value: section.title)
                Text("Select an item to see its details here.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Inspector")
    }
}
