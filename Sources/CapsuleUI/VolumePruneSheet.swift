//
//  VolumePruneSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The volume Clean Up sheet: a best-effort preview of the zero-attachment volumes a prune
//  would remove, then the actual reclaimed result after running. The runtime owns the
//  authoritative reference check, so the preview is labelled best-effort.

import CapsuleDomain
import SwiftUI

struct VolumePruneSheet: View {
    let actions: VolumeActionsModel
    let onClose: () -> Void

    @State private var targets: [Volume] = []
    @State private var isLoading = true
    @State private var isPruning = false
    @State private var resultMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Clean Up Volumes", systemImage: "trash")
                .font(.headline)

            if let resultMessage {
                Text(resultMessage).font(.callout)
            } else if isLoading {
                ProgressView("Finding unused volumes…")
            } else if targets.isEmpty {
                Text("No unused volumes to remove.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(targets.count) volume(s) will be removed:")
                    .font(.callout)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(targets) { volume in
                            Text("• \(volume.name)")
                                .font(.system(.callout, design: .monospaced))
                        }
                    }
                }
                .frame(maxHeight: 160)
                Text(
                    "This preview is best-effort; the runtime decides the final set. The "
                        + "actual reclaimed result is shown after cleanup."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button(resultMessage == nil ? "Cancel" : "Done", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if resultMessage == nil {
                    Button("Clean Up", role: .destructive) {
                        Task {
                            isPruning = true
                            let summary = await actions.prune()
                            resultMessage = summary.message
                            isPruning = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || isPruning)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { await reloadTargets() }
    }

    private func reloadTargets() async {
        isLoading = true
        targets = await actions.computePruneTargets()
        isLoading = false
    }
}
