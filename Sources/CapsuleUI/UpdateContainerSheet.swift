//
//  UpdateContainerSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Confirmation sheet for updating the container CLI: explains the Terminal handoff
//  (stop services → sudo updater → restart), previews the exact script, and only then
//  hands off — or, when the updater script is missing, offers the installer download.

import CapsuleDomain
import SwiftUI

struct UpdateContainerSheet: View {
    let scriptPreview: String
    let updaterScriptAvailable: Bool
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Update container")
                .font(.title2.bold())
            if updaterScriptAvailable {
                Text(
                    "Capsule stops container services, then opens Terminal to run Apple's "
                        + "updater script. Terminal asks for your administrator password "
                        + "(sudo); services restart after a successful update."
                )
                .foregroundStyle(.secondary)
                GroupBox {
                    Text(scriptPreview)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(
                    "The updater script was not found at "
                        + "/usr/local/bin/update-container.sh. Capsule will download the "
                        + "latest signed installer package instead — finish the update in "
                        + "Installer."
                )
                .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("update-container-cancel")
                Button(updaterScriptAvailable ? "Open Terminal & Update" : "Download Installer") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("update-container-confirm")
            }
        }
        .padding(20)
        .frame(width: 480)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("update-container-sheet")
    }
}
