//
//  RunFailureTriageView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Shown inline in the Quick Run sheet when a detached run fails. It keeps the full raw
//  transcript visible and offers the three triage paths: resolve the image (pull it),
//  inspect the logs (the transcript is right here), and retry the run in a terminal.

import CapsuleDomain
import SwiftUI

struct RunFailureTriageView: View {
    let task: OperationTask
    let imageReference: String?
    var onResolveImage: () -> Void
    var onRetryInTerminal: () -> Void

    /// The Resolve Image tooltip, localized. Names the missing image reference when known,
    /// otherwise falls back to a fully localized "the image" phrasing (no interpolation).
    private var resolveImageHelp: Text {
        if let imageReference {
            return Text("Pull \(imageReference) from a registry", bundle: .module)
        }
        return Text("Pull the image from a registry", bundle: .module)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The container didn’t start", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)

            Text(
                "The raw output is below. Resolve the image if it’s missing, or rerun in a "
                    + "terminal to watch it interactively."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    onResolveImage()
                } label: {
                    Label("Resolve Image", systemImage: "arrow.down.circle")
                }
                .help(resolveImageHelp)

                Button {
                    onRetryInTerminal()
                } label: {
                    Label("Retry in Terminal", systemImage: "terminal")
                }
            }

            // Inspect Logs: the failing transcript is kept visible (never hidden on failure).
            TaskTranscriptView(task: task)
        }
        .padding(.top, 4)
    }
}
