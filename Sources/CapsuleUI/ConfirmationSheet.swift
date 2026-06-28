//
//  ConfirmationSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  One generic sheet for every destructive confirmation, driven by the domain's pure
//  `ConfirmationRequest` value type.

import CapsuleDomain
import SwiftUI

struct ConfirmationSheet: View {
    let request: ConfirmationRequest
    let onConfirm: (ConfirmationRequest) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(request.title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(request.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(request.confirmTitle, role: .destructive) { onConfirm(request) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
