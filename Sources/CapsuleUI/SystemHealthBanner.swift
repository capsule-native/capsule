//
//  SystemHealthBanner.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The global system-health banner. It is the shell's signature element: a colored status
//  dot, a one-line headline, and the recovery actions for the current state. The
//  presentation logic lives in pure `bannerText` / `recoveryActions` helpers so it can be
//  unit-tested without rendering.

import CapsuleDomain
import SwiftUI

public struct SystemHealthBanner: View {
    /// The text and tint a banner should show for a given health state.
    public struct BannerText: Equatable {
        public var title: String
        public var message: String
        public var kind: BannerKind
    }

    let health: SystemHealth
    let compatibilityWarning: String?
    let onRecover: (RecoveryAction) -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    public init(
        health: SystemHealth,
        compatibilityWarning: String?,
        onRecover: @escaping (RecoveryAction) -> Void
    ) {
        self.health = health
        self.compatibilityWarning = compatibilityWarning
        self.onRecover = onRecover
    }

    public var body: some View {
        let text = Self.bannerText(for: health, warning: compatibilityWarning)
        let actions = Self.recoveryActions(for: health)

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill(CapsuleColors.accent(for: text.kind))
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(text.title)
                    .font(.headline)
                Text(text.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button(action.title) { onRecover(action) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(CapsuleColors.accent(for: text.kind))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CapsuleColors.bannerBackground(text.kind, contrast: contrast))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CapsuleColors.bannerBorder(text.kind, contrast: contrast))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(text.title). \(text.message)", bundle: .module))
        .accessibilityIdentifier("system-health-banner")
    }

    // MARK: - Pure presentation (unit-tested)

    /// The headline, supporting line, and tint for a health state. A non-nil compatibility
    /// warning on a *running* service downgrades the tint to caution and is shown as the
    /// supporting line.
    public static func bannerText(for health: SystemHealth, warning: String?) -> BannerText {
        switch health {
        case .unknown, .checking:
            return BannerText(
                title: "Checking services…",
                message: "Connecting to the container service.",
                kind: .info)

        case let .running(version, _):
            let versionLine = versionDescription(version)
            if let warning {
                return BannerText(
                    title: "Container services are running", message: warning,
                    kind: .caution)
            }
            return BannerText(
                title: "Container services are running", message: versionLine, kind: .healthy)

        case .stopped:
            return BannerText(
                title: "Container services are stopped",
                message: "Start the container service to manage containers, images, and more.",
                kind: .unhealthy)

        case let .unavailable(detail):
            return BannerText(title: detail.title, message: detail.explanation, kind: .unhealthy)

        case let .notInstalled(detail):
            return BannerText(title: detail.title, message: detail.explanation, kind: .unhealthy)
        }
    }

    /// The recovery actions to offer for a health state.
    public static func recoveryActions(for health: SystemHealth) -> [RecoveryAction] {
        switch health {
        case .unknown, .checking, .running:
            return []
        case .stopped:
            return [.startServices, .openLogs]
        case let .unavailable(detail):
            return detail.recoveryActions
        case let .notInstalled(detail):
            return detail.recoveryActions
        }
    }

    /// A compact "container 1.0.0 · service 1.0.0" readout.
    private static func versionDescription(_ version: SystemVersion) -> String {
        var line = "container \(version.client)"
        if let server = version.server {
            line += " · service \(server)"
        }
        return line
    }
}
