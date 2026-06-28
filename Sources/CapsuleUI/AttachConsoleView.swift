//
//  AttachConsoleView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The read-only attach console. Streams a container's `logs --follow` output; the stream is
//  the `container logs` process's pipes, not the workload's stdout/stderr (labelled
//  honestly). "Open Shell" opens an interactive shell in the embedded terminal.

import CapsuleDomain
import SwiftUI

struct AttachConsoleView: View {
    let session: AttachSession
    let terminalAvailable: Bool
    let onDetach: () -> Void
    let onRetry: () -> Void
    let onOpenShell: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            console
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Read-only", systemImage: "eye")
                .font(.caption)
                .foregroundStyle(.secondary)
            statusFooter
            Spacer()
            Button("Open Shell", action: onOpenShell)
                .disabled(!terminalAvailable)
                .help(
                    terminalAvailable
                        ? "Open an interactive shell in the embedded terminal"
                        : "Start the container to open a shell")
            if case .failed = session.phase {
                Button("Retry Attach", action: onRetry)
            }
            Button("Detach", action: onDetach)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusFooter: some View {
        switch session.phase {
        case .streaming:
            Label("Streaming", systemImage: "dot.radiowaves.left.and.right")
                .font(.caption).foregroundStyle(.green)
        case .ended:
            Text("Ended").font(.caption).foregroundStyle(.secondary)
        case .failed(let detail):
            Label(detail.title, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private var console: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(session.lines) { line in
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(line.stream == .error ? .orange : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: session.lines.count) {
                if let last = session.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}
