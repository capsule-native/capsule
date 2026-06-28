//
//  ActivityPaneView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The persistent bottom utility pane: a tab strip for Logs / Tasks / Progress plus a
//  reserved slot for a detachable terminal (wired in a later milestone). Content is
//  placeholder today; the frame, tabs, and the activity log feed are real.

import CapsuleDomain
import SwiftUI

struct ActivityPaneView: View {
    @Bindable var shell: ShellState
    /// Recent activity lines (newest last) surfaced by the system model.
    let activityLog: [String]

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 160)
        .background(CapsuleColors.activitySurface)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Activity", selection: $shell.activityTab) {
                ForEach(ActivityTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbolName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            Button {
                shell.toggleActivityPane()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Hide the Activity pane")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        switch shell.activityTab {
        case .logs:
            logsList
        case .tasks:
            placeholder("No running tasks", systemImage: "checklist")
        case .progress:
            placeholder("No active transfers", systemImage: "chart.bar")
        }
    }

    private var logsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if activityLog.isEmpty {
                    Text("Activity will appear here.")
                        .foregroundStyle(.secondary)
                        .padding(8)
                } else {
                    ForEach(Array(activityLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func placeholder(_ title: String, systemImage: String) -> some View {
        VStack {
            Spacer()
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
