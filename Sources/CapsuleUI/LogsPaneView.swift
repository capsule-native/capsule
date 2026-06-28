//
//  LogsPaneView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  A logs surface backed by `LogsModel`: follow toggle, tail count, boot toggle, search, and
//  a save-transcript action over an auto-scrolling monospaced scrollback. Reused by both the
//  embedded pane and the detachable log window.

import AppKit
import CapsuleDomain
import SwiftUI

struct LogsPaneView: View {
    @Bindable var model: LogsModel
    /// Shown by the detachable window only (the embedded pane omits it).
    var onOpenInWindow: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            scrollback
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Toggle("Follow", isOn: $model.follow)
                .toggleStyle(.switch)
                .controlSize(.mini)
            HStack(spacing: 4) {
                Text("Tail").font(.caption).foregroundStyle(.secondary)
                TextField("all", value: $model.tail, format: .number)
                    .frame(width: 56)
                    .textFieldStyle(.roundedBorder)
            }
            Toggle("Boot", isOn: $model.boot)
                .controlSize(.mini)
            Button {
                if let id = model.containerID { model.start(id: id) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload with the current follow / tail / boot settings")
            .disabled(model.containerID == nil)

            TextField("Search", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120)

            Button {
                saveTranscript()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Save the transcript")
            .disabled(model.lines.isEmpty)

            if let onOpenInWindow {
                Button {
                    onOpenInWindow()
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                }
                .help("Open the logs in a separate window")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var scrollback: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.filteredLines) { line in
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(line.stream == .error ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(line.id)
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(8)
            }
            .background(CapsuleColors.activitySurface)
            .onChange(of: model.lines.count) {
                withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            }
            .overlay {
                if model.containerID == nil {
                    ContentUnavailableView(
                        "No logs", systemImage: "doc.plaintext",
                        description: Text("Choose a container’s Logs… action to stream its output.")
                    )
                }
            }
        }
    }

    private let bottomAnchor = "logs-bottom-anchor"

    private func saveTranscript() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(model.containerID ?? "container")-logs.txt"
        panel.allowedContentTypes = [.plainText, .log]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? model.transcriptText.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
