//
//  UpdatesSettingsView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Preferences “Updates” tab: the familiar, lightweight Sparkle surface — a Check for
//  Updates button, an automatic-check toggle, and the last-check time. Binds to the
//  `UpdaterController` seam, so it shows real Sparkle state in the app and inert no-op state
//  in previews/tests.

import SwiftUI

public struct UpdatesSettingsView: View {
    private let updater: any UpdaterController

    public init(updater: any UpdaterController) {
        self.updater = updater
    }

    public var body: some View {
        Form {
            Section("Software Updates") {
                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 })
                )
                .accessibilityIdentifier("updates-auto-check-toggle")

                LabeledContent("Last checked", value: lastCheckedText)

                HStack {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                        .accessibilityIdentifier("updates-check-button")
                    Spacer()
                }
            }

            Section {
                Label {
                    Text(
                        "Updates are delivered by Sparkle from the project's signed release feed, "
                            + "downloaded over HTTPS and verified with an EdDSA signature before they "
                            + "install. Capsule is unsandboxed and notarized with a hardened runtime."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "lock.shield")
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("updates-settings-page")
    }

    private var lastCheckedText: String {
        guard let date = updater.lastUpdateCheckDate else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
