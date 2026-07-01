//
//  PrivacyView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The in-app Privacy page (Preferences → Privacy). Renders `PrivacyDisclosure` verbatim so
//  what the user reads is the same posture the code enforces (see DiagnosticOptions).

import CapsuleDomain
import SwiftUI

public struct PrivacyView: View {
    private let disclosure: PrivacyDisclosure

    public init(disclosure: PrivacyDisclosure = .default) {
        self.disclosure = disclosure
    }

    public var body: some View {
        Form {
            Section {
                Text(
                    "Capsule keeps your data on your Mac. Here is exactly what is collected — all "
                        + "of it local-only or opt-in — and what is never collected."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section("Collected") {
                ForEach(disclosure.collected) { item in
                    disclosureRow(item, systemImage: "checkmark.shield", tint: .green)
                }
            }

            Section("Never collected") {
                ForEach(disclosure.neverCollected) { item in
                    disclosureRow(item, systemImage: "hand.raised.slash", tint: .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("privacy-page")
    }

    private func disclosureRow(
        _ item: PrivacyDisclosure.Item, systemImage: String, tint: Color
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }
}
