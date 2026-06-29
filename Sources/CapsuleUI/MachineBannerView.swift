//
//  MachineBannerView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import SwiftUI

/// Transient action banner surfaced from `MachineActionsModel.banner`.
///
/// Rendered at the top of `MachineListView` as a `.safeAreaInset`. Each `MachineBanner.Kind`
/// shows a different set of trailing action buttons; Dismiss always clears `actions.banner`.
struct MachineBannerView: View {
    @Bindable var actions: MachineActionsModel

    @Environment(\.colorSchemeContrast) private var contrast

    private var banner: MachineBanner? { actions.banner }

    var body: some View {
        if let banner {
            row(for: banner)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.22), value: banner.id)
        }
    }

    // MARK: - Per-kind layout

    @ViewBuilder
    private func row(for banner: MachineBanner) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: iconName(for: banner.kind))
                .foregroundStyle(tintColor(for: banner.kind))
                .font(.system(size: 16, weight: .medium))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.headline)
                Text(banner.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                actionButtons(for: banner)
                Button("Dismiss") { actions.banner = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            tintColor(for: banner.kind).opacity(contrast == .increased ? 0.28 : 0.14)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tintColor(for: banner.kind).opacity(contrast == .increased ? 0.9 : 0.35))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(banner.title). \(banner.message)")
    }

    // MARK: - Action buttons per kind

    @ViewBuilder
    private func actionButtons(for banner: MachineBanner) -> some View {
        switch banner.kind {
        case .created:
            EmptyView()

        case .implicitBoot:
            EmptyView()

        case let .stopped(name):
            Button("Open Shell") { actions.openShell(name: name) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(tintColor(for: banner.kind))
            Button("Restart") {
                Task { await actions.restartNow(name) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case let .madeDefault(_, previous):
            if previous != nil {
                Button("Undo") {
                    Task { await actions.revertDefault() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(tintColor(for: banner.kind))
            }
        }
    }

    // MARK: - Visual helpers

    private func iconName(for kind: MachineBanner.Kind) -> String {
        switch kind {
        case .created: "checkmark.circle.fill"
        case .implicitBoot: "arrow.clockwise.circle"
        case .stopped: "stop.circle.fill"
        case .madeDefault: "star.circle.fill"
        }
    }

    private func tintColor(for kind: MachineBanner.Kind) -> Color {
        switch kind {
        case .created: .green
        case .implicitBoot: .blue
        case .stopped: .secondary
        case .madeDefault: .yellow
        }
    }
}
