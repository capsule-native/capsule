//
//  TaskTranscriptView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  A single long-operation task: its state, a scrollable raw transcript (kept visible on
//  failure so registry/auth/platform errors are never hidden), and a Retry on failure.
//  Reused by the Activity pane's Tasks tab and the transfer sheets.

import CapsuleDomain
import SwiftUI

struct TaskTranscriptView: View {
    let task: OperationTask
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                stateIcon
                Text(task.title).font(.callout.weight(.medium))
                Spacer()
                if task.transcript.isEmpty == false {
                    Button {
                        Pasteboard.copy(task.transcriptText)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy transcript")
                }
                if isFailed, let onRetry {
                    Button("Retry", action: onRetry)
                }
            }

            if !task.transcript.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(task.transcript) { line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(color(for: line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 160)
                .background(CapsuleColors.activitySurface)
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = task.state { return true }
        return false
    }

    /// stdout is primary; stderr is dimmed while running/succeeding (many CLIs emit progress
    /// there) and only turns red once the task has actually failed, so a successful pull
    /// never looks alarming.
    private func color(for line: LogLine) -> Color {
        guard line.stream == .error else { return .primary }
        return isFailed ? .red : .secondary
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch task.state {
        case .idle, .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
