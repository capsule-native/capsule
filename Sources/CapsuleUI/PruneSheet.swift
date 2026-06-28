//
//  PruneSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Cleanup sheet: precomputes the stopped containers prune would remove (count + names),
//  is honest that a freed-space estimate is unavailable, and reports the actual reclaimed
//  result after running.

import CapsuleDomain
import SwiftUI

struct PruneSheet: View {
    let lifecycle: ContainerLifecycleModel
    let onClose: () -> Void

    @State private var targets: [Container] = []
    @State private var isLoading = true
    @State private var isPruning = false
    @State private var resultMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Clean Up Stopped Containers", systemImage: "trash")
                .font(.headline)

            if let resultMessage {
                Text(resultMessage).font(.callout)
            } else if isLoading {
                ProgressView("Finding stopped containers…")
            } else if targets.isEmpty {
                Text("No stopped containers to remove.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(targets.count) stopped container(s) will be removed:")
                    .font(.callout)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(targets) { container in
                            Text("• \(container.name)")
                                .font(.system(.callout, design: .monospaced))
                        }
                    }
                }
                .frame(maxHeight: 160)
                Text(
                    "Freed space can't be estimated in advance; the amount reclaimed is shown after cleanup."
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
                            let summary = await lifecycle.prune()
                            resultMessage = summary.message
                            isPruning = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || targets.isEmpty || isPruning)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .task {
            targets = await lifecycle.computePruneTargets()
            isLoading = false
        }
    }
}
