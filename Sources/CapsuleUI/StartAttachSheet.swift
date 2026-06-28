//
//  StartAttachSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The optional attach sheet for Start. Explains the read-only attach interim and the
//  disabled exec-shell, then starts (with or without attaching).

import SwiftUI

struct StartAttachSheet: View {
    let containerName: String
    let terminalAvailable: Bool
    let onStart: (_ attach: Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start “\(containerName)”")
                .font(.headline)

            Text(
                "Attaching streams the container's output here, read-only. "
                    + "An interactive shell arrives with the embedded terminal update."
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
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
