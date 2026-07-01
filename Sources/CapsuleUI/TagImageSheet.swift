//
//  TagImageSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Creates a new reference for an existing image. The source — including its digest — stays
//  visible so the user always knows exactly which image they are retagging.

import CapsuleDomain
import SwiftUI

struct TagImageSheet: View {
    let sourceReference: String
    let sourceDigest: String
    let onTag: (String) -> Void
    let onCancel: () -> Void
    let invocationFor: (String) -> CommandInvocation

    @State private var target = ""

    private var trimmedTarget: String {
        target.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Tag Image", systemImage: "tag")
                .font(.headline)

            Form {
                LabeledContent("Source", value: sourceReference)
                LabeledContent("Digest") {
                    Text(sourceDigest).font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1).truncationMode(.middle)
                }
                TextField("New reference", text: $target, prompt: Text("e.g. ghcr.io/me/app:1.0"))
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)

            CommandPreviewView(invocationFor(trimmedTarget))

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Tag") { onTag(trimmedTarget) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedTarget.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
