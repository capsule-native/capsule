//
//  PullImageSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Pull an image by reference, with an optional platform constraint. Once started, the live
//  transcript stays in the sheet so registry/auth/platform errors are visible without
//  leaving the dialog; the task also lives on in the Activity pane.

import CapsuleDomain
import SwiftUI

struct PullImageSheet: View {
    let onPull: (String, String?) -> OperationTask
    let onRetry: (OperationTask) -> Void
    let onClose: () -> Void

    @State private var reference: String
    @State private var platform = ""
    @State private var task: OperationTask?

    init(
        initialReference: String = "",
        onPull: @escaping (String, String?) -> OperationTask,
        onRetry: @escaping (OperationTask) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onPull = onPull
        self.onRetry = onRetry
        self.onClose = onClose
        self._reference = State(initialValue: initialReference)
    }

    private var trimmedReference: String {
        reference.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Pull Image", systemImage: "arrow.down.circle")
                .font(.headline)

            if let task {
                TaskTranscriptView(task: task, onRetry: { onRetry(task) })
                HStack {
                    Spacer()
                    Button("Done", action: onClose).keyboardShortcut(.defaultAction)
                }
            } else {
                Form {
                    TextField(
                        "Reference", text: $reference,
                        prompt: Text("e.g. docker.io/library/alpine:latest"))
                    TextField(
                        "Platform (optional)", text: $platform,
                        prompt: Text("e.g. linux/arm64"))
                }
                .formStyle(.grouped)

                HStack {
                    Button("Cancel", role: .cancel, action: onClose)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Pull") {
                        let plat = platform.trimmingCharacters(in: .whitespacesAndNewlines)
                        task = onPull(trimmedReference, plat.isEmpty ? nil : plat)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedReference.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
