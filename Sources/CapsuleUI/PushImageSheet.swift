//
//  PushImageSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Push an image to its registry. The destination is shown prominently and a confirmation
//  step guards against an accidental push to the wrong repository. The live transcript stays
//  in the sheet so auth/registry errors are visible.

import CapsuleDomain
import SwiftUI

struct PushImageSheet: View {
    let initialReference: String
    let initialDigest: String
    let onPush: (String, String?) -> OperationTask
    let onRetry: (OperationTask) -> Void
    let onClose: () -> Void
    let invocationFor: (String, String?) -> CommandInvocation

    @State private var reference: String
    @State private var platform = ""
    @State private var confirming = false
    @State private var task: OperationTask?

    init(
        initialReference: String,
        initialDigest: String,
        onPush: @escaping (String, String?) -> OperationTask,
        onRetry: @escaping (OperationTask) -> Void,
        onClose: @escaping () -> Void,
        invocationFor: @escaping (String, String?) -> CommandInvocation
    ) {
        self.initialReference = initialReference
        self.initialDigest = initialDigest
        self.onPush = onPush
        self.onRetry = onRetry
        self.onClose = onClose
        self.invocationFor = invocationFor
        _reference = State(initialValue: initialReference)
    }

    private var trimmedReference: String {
        reference.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The registry host the push targets. A reference with no `/` is a Docker Hub image
    /// (`alpine:latest`), so its leading segment is the repo, never the host — only treat the
    /// first path segment as a host when it actually looks like one.
    private var destination: String {
        guard let first = trimmedReference.split(separator: "/").first,
            trimmedReference.contains("/")
        else { return "docker.io" }
        let host = String(first)
        return host.contains(".") || host.contains(":") || host == "localhost" ? host : "docker.io"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Push Image", systemImage: "arrow.up.circle")
                .font(.headline)

            if let task {
                TaskTranscriptView(task: task, onRetry: { onRetry(task) })
                HStack {
                    Spacer()
                    Button("Done", action: onClose).keyboardShortcut(.defaultAction)
                }
            } else {
                Form {
                    LabeledContent("Digest") {
                        Text(initialDigest).font(.system(.callout, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    TextField("Reference (tag) to push", text: $reference)
                    TextField(
                        "Platform (optional)", text: $platform, prompt: Text("e.g. linux/amd64"))
                    LabeledContent("Destination", value: destination)
                }
                .formStyle(.grouped)

                CommandPreviewView(
                    invocationFor(trimmedReference, platform.isEmpty ? nil : platform))

                HStack {
                    Button("Cancel", role: .cancel, action: onClose)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Push…") { confirming = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmedReference.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .confirmationDialog(
            "Push “\(trimmedReference)” to \(destination)?",
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Push to \(destination)") {
                let plat = platform.trimmingCharacters(in: .whitespacesAndNewlines)
                task = onPush(trimmedReference, plat.isEmpty ? nil : plat)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Make sure the destination repository is correct before continuing.")
        }
    }
}
