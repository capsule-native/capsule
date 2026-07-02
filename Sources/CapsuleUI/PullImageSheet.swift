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

/// Where the Pull Image sheet's reference comes from: typed by hand, or picked from the
/// Docker Hub browse pane.
enum PullSheetSource {
    case reference
    case browse
}

struct PullImageSheet: View {
    let searchModel: RegistrySearchModel?
    let onPull: (String, String?) -> OperationTask
    let onRetry: (OperationTask) -> Void
    let onClose: () -> Void
    let invocationFor: (String, String?) -> CommandInvocation

    @State private var reference: String
    @State private var platform = ""
    @State private var task: OperationTask?
    @State private var source: PullSheetSource = .reference

    init(
        initialReference: String = "",
        searchModel: RegistrySearchModel? = nil,
        onPull: @escaping (String, String?) -> OperationTask,
        onRetry: @escaping (OperationTask) -> Void,
        onClose: @escaping () -> Void,
        invocationFor: @escaping (String, String?) -> CommandInvocation
    ) {
        self.searchModel = searchModel
        self.onPull = onPull
        self.onRetry = onRetry
        self.onClose = onClose
        self.invocationFor = invocationFor
        self._reference = State(initialValue: initialReference)
    }

    private var trimmedReference: String {
        reference.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Pull Image", systemImage: "arrow.down.circle")
                .font(.headline)

            if task == nil, searchModel != nil {
                Picker("Source", selection: $source) {
                    Text("Reference", bundle: .module).tag(PullSheetSource.reference)
                    Text("Browse", bundle: .module).tag(PullSheetSource.browse)
                }
                .pickerStyle(.segmented)
            }

            if let task {
                TaskTranscriptView(task: task, onRetry: { onRetry(task) })
                HStack {
                    Spacer()
                    Button("Done", action: onClose).keyboardShortcut(.defaultAction)
                }
            } else if source == .browse, let searchModel {
                RegistryBrowseView(model: searchModel) { picked in
                    searchModel.clearSelection()
                    reference = picked
                    source = .reference
                }
                HStack {
                    Button("Cancel", role: .cancel, action: onClose)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
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

                CommandPreviewView(
                    invocationFor(trimmedReference, platform.isEmpty ? nil : platform))

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
        .frame(
            width: isBrowsing ? 560 : 480,
            height: isBrowsing ? 620 : nil
        )
        // Each presentation starts at the search stage; the shared model keeps its query
        // and caches, but never a previous session's tag drill-in.
        .onAppear { searchModel?.clearSelection() }
    }

    /// True while the Browse pane is showing; the sheet grows to list-friendly dimensions
    /// (BuildSheet/QuickRunSheet precedent) and returns to the intrinsic-height reference
    /// form everywhere else — including the transcript, which keeps its original frame.
    private var isBrowsing: Bool {
        source == .browse && task == nil && searchModel != nil
    }
}
