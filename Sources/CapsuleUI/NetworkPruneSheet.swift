//
//  NetworkPruneSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The network Clean Up sheet: precompute a best-effort preview of zero-connection networks
//  (builtins excluded), then report the actual reclaimed result after running. Honest that
//  the runtime owns the final set — mirrors ImagePruneSheet.

import CapsuleDomain
import SwiftUI

struct NetworkPruneSheet: View {
    let actions: NetworkActionsModel
    let onClose: () -> Void

    @State private var targets: [CapsuleDomain.Network] = []
    @State private var isLoading = true
    @State private var isPruning = false
    @State private var resultMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Clean Up Networks", systemImage: "trash")
                .font(.headline)

            if let resultMessage {
                Text(resultMessage).font(.callout)
            } else if isLoading {
                ProgressView("Finding networks…")
            } else if targets.isEmpty {
                Text("No unused networks to remove.")
                    .foregroundStyle(.secondary)
            } else {
                Text("^[\(targets.count) network](inflect: true) will be removed:", bundle: .module)
                    .font(.callout)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(targets) { network in
                            Text("• \(network.name)\(network.ipv4Subnet.map { "  \($0)" } ?? "")")
                                .font(.system(.callout, design: .monospaced))
                        }
                    }
                }
                .frame(maxHeight: 160)
                Text(
                    "This preview is best-effort; the runtime decides the final set. Builtin "
                        + "networks are never removed. The actual result is shown after cleanup."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            CommandPreviewView(actions.pruneInvocation)

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
