//
//  OnboardingView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  First-launch onboarding. It introduces Capsule, reflects the live service status, and
//  lets the user start the service before they reach the shell. Presentation (the
//  first-launch gate via `@AppStorage`) is owned by `RootView`.

import CapsuleDomain
import SwiftUI

public struct OnboardingView: View {
    let health: SystemHealth
    let actions: ShellActions
    let onFinish: () -> Void

    public init(
        health: SystemHealth,
        actions: ShellActions,
        onFinish: @escaping () -> Void
    ) {
        self.health = health
        self.actions = actions
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Welcome to Capsule")
                    .font(.largeTitle.bold())
                Text("Manage containers, images, volumes, and networks on your Mac.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            serviceStatusCard

            HStack(spacing: 12) {
                if health.isRunning {
                    Button("Get Started", action: onFinish)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Start Services") { actions.recover(.startServices) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Button("Continue", action: onFinish)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(40)
        .frame(width: 520)
    }

    private var serviceStatusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(CapsuleColors.accent(for: health.bannerKind))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(cardTitle).font(.headline)
                Text(cardMessage).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CapsuleColors.bannerBackground(health.bannerKind, contrast: .standard))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var cardTitle: String {
        health.isRunning ? "Container services are running" : "Container services are not running"
    }

    private var cardMessage: String {
        if case let .running(version, _) = health {
            return "Connected to container \(version.client)."
        }
        return "Start the service now, or do it later from the System section."
    }
}
