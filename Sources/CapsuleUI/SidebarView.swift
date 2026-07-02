//
//  SidebarView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import SwiftUI

/// The resource sidebar. Resource sections are disabled while their feature family is
/// unavailable; the System section is always reachable. Overall service health is shown
/// by the banner at the top of the detail column, so the sidebar carries no status dot.
struct SidebarView: View {
    @Bindable var shell: ShellState
    let availableFeatures: Set<SystemFeature>

    private var resourceSections: [SidebarSection] {
        SidebarSection.allCases.filter { $0 != .system }
    }

    var body: some View {
        List(selection: $shell.selection) {
            Section("Resources") {
                ForEach(resourceSections) { section in
                    row(section)
                }
            }
            Section {
                row(.system)
            }
        }
        .navigationTitle("Capsule")
    }

    private func row(_ section: SidebarSection) -> some View {
        let enabled = section.isEnabled(features: availableFeatures)
        return Label {
            Text(section.localizedTitle)
        } icon: {
            Image(systemName: section.symbolName)
        }
        .tag(section)
        .disabled(!enabled)
        .foregroundStyle(enabled ? .primary : .secondary)
        // Stable identifier for golden UI tests (e.g. "sidebar-containers").
        .accessibilityIdentifier("sidebar-\(String(describing: section))")
    }
}
