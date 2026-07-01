//
//  SidebarView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import SwiftUI

/// The resource sidebar. Resource sections are disabled while their feature family is
/// unavailable; the System section is always reachable. A status dot at the bottom
/// reflects overall health so the user can see at a glance whether the service is up.
struct SidebarView: View {
    @Bindable var shell: ShellState
    let availableFeatures: Set<SystemFeature>
    let bannerKind: BannerKind
    let statusLabel: LocalizedStringResource

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
        .safeAreaInset(edge: .bottom) {
            statusFooter
        }
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
    }

    private var statusFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(CapsuleColors.accent(for: bannerKind))
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("Service status: \(String(localized: statusLabel))", bundle: .module))
    }
}
