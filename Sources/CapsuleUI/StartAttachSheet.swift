//
//  StartAttachSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The optional attach sheet for Start. Offers read-only attach (logs --follow) and an
//  interactive "Start in Terminal" (start -ai in the embedded terminal).

import SwiftUI

struct StartAttachSheet: View {
    let containerName: String
    let terminalAvailable: Bool
    let onStart: (_ attach: Bool) -> Void
    let onStartInTerminal: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start “\(containerName)”", bundle: .module)
                .font(.headline)

            Text(
                "Attaching streams the container's output here, read-only. "
                    + "Start in Terminal runs it interactively in the embedded terminal."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start") { onStart(false) }
                Button("Start and Attach") { onStart(true) }
                if terminalAvailable {
                    Button("Start in Terminal", action: onStartInTerminal)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
