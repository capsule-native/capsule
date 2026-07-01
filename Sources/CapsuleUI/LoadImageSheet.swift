//
//  LoadImageSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Import images from an OCI-compatible tar archive: pick a file or drag one in. The archive
//  type is validated before the backend is invoked, and the live transcript stays visible so
//  a malformed archive surfaces a clear error.

import CapsuleDomain
import SwiftUI
import UniformTypeIdentifiers

struct LoadImageSheet: View {
    let onLoad: (URL) -> OperationTask
    let onRetry: (OperationTask) -> Void
    let onClose: () -> Void
    let invocationFor: (URL) -> CommandInvocation

    @State private var selectedURL: URL?
    @State private var validationError: String?
    @State private var isTargeted = false
    @State private var importing = false
    @State private var task: OperationTask?

    /// Archive shapes the backend accepts: a tar (optionally gzipped) or an OCI directory.
    private static let allowedExtensions: Set<String> = ["tar", "gz", "tgz"]

    init(
        onLoad: @escaping (URL) -> OperationTask,
        onRetry: @escaping (OperationTask) -> Void,
        onClose: @escaping () -> Void,
        invocationFor: @escaping (URL) -> CommandInvocation
    ) {
        self.onLoad = onLoad
        self.onRetry = onRetry
        self.onClose = onClose
        self.invocationFor = invocationFor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Load Image", systemImage: "square.and.arrow.up")
                .font(.headline)

            if let task {
                TaskTranscriptView(task: task, onRetry: { onRetry(task) })
                HStack {
                    Spacer()
                    Button("Done", action: onClose).keyboardShortcut(.defaultAction)
                }
            } else {
                dropZone

                if let selectedURL {
                    LabeledContent("Selected", value: selectedURL.lastPathComponent)
                }
                if let selectedURL {
                    CommandPreviewView(invocationFor(selectedURL))
                }
                if let validationError {
                    Label(validationError, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }

                HStack {
                    Button("Cancel", role: .cancel, action: onClose)
                        .keyboardShortcut(.cancelAction)
                    Button("Choose File…") { importing = true }
                    Spacer()
                    Button("Load") {
                        if let url = selectedURL { task = onLoad(url) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedURL == nil)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .fileImporter(
            isPresented: $importing, allowedContentTypes: [.data, .directory],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first { validate(url) }
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                style: StrokeStyle(lineWidth: 1.5, dash: [6])
            )
            .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            .frame(height: 80)
            .overlay {
                Label("Drag a .tar archive here", systemImage: "tray.and.arrow.down")
                    .foregroundStyle(.secondary)
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in validate(url) } }
                }
                return true
            }
    }

    /// Validates the archive type before the backend is ever invoked.
    private func validate(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if url.hasDirectoryPath || Self.allowedExtensions.contains(ext) {
            selectedURL = url
            validationError = nil
        } else {
            selectedURL = nil
            validationError = "“\(url.lastPathComponent)” isn’t a .tar archive or OCI directory."
        }
    }
}
