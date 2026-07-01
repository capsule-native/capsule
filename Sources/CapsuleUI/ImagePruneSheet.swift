//
//  ImagePruneSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The image Clean Up sheet: a scope toggle (dangling-only vs all unused) drives a live
//  preview of exactly which images would be reclaimed, and reports the actual reclaimed
//  result after running. Honest that the freed-space amount is only known afterwards.

import CapsuleDomain
import SwiftUI

struct ImagePruneSheet: View {
    let actions: ImageActionsModel
    let onClose: () -> Void

    @State private var scope: PruneScope = .dangling
    @State private var targets: [CapsuleDomain.Image] = []
    @State private var isLoading = true
    @State private var isPruning = false
    @State private var resultMessage: String?

    private enum PruneScope: String, CaseIterable, Identifiable {
        case dangling
        case allUnused
        var id: String { rawValue }
        var title: String { self == .dangling ? "Dangling only" : "All unused" }
        var isAll: Bool { self == .allUnused }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Clean Up Images", systemImage: "trash")
                .font(.headline)

            if resultMessage == nil {
                Picker("Scope", selection: $scope) {
                    ForEach(PruneScope.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(isPruning)
            }

            if let resultMessage {
                Text(resultMessage).font(.callout)
            } else if isLoading {
                ProgressView("Finding images…")
            } else if targets.isEmpty {
                Text("No \(scope == .dangling ? "dangling" : "unused") images to remove.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(targets.count) image(s) will be removed:")
                    .font(.callout)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(targets) { image in
                            Text("• \(image.displayName)  \(image.shortDigest)")
                                .font(.system(.callout, design: .monospaced))
                        }
                    }
                }
                .frame(maxHeight: 160)
                Text(
                    scope.isAll
                        ? "This preview is best-effort; the runtime decides the final set. Freed "
                            + "space is shown after cleanup."
                        : "Freed space can't be estimated in advance; the amount reclaimed is "
                            + "shown after."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            CommandPreviewView(actions.pruneInvocation(all: scope.isAll))

            HStack {
                Button(resultMessage == nil ? "Cancel" : "Done", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if resultMessage == nil {
                    Button("Clean Up", role: .destructive) {
                        Task {
                            isPruning = true
                            let summary = await actions.prune(all: scope.isAll)
                            resultMessage = summary.message
                            isPruning = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    // Dangling detection is reliable, so block on an empty preview there. The
                    // all-unused preview is heuristic, so never block a prune the CLI would run.
                    .disabled(isLoading || isPruning || (scope == .dangling && targets.isEmpty))
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .task(id: scope) { await reloadTargets() }
    }

    private func reloadTargets() async {
        isLoading = true
        targets = await actions.computePruneTargets(all: scope.isAll)
        isLoading = false
    }
}
