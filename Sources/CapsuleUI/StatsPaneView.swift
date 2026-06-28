//
//  StatsPaneView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The container metrics pane shown in the inspector's Summary tab: labeled CPU / memory /
//  network / block-IO / process count, plus a Live/Snapshot toggle. Live updates refresh
//  on a ~2 s floor (the CLI's own double-sample), so the UI doesn't promise sub-second ticks.

import CapsuleDomain
import SwiftUI

struct StatsPaneView: View {
    let metrics: ContainerMetrics?
    let isStreaming: Bool
    let onToggleLive: (Bool) -> Void

    var body: some View {
        Section("Resources") {
            Toggle("Live", isOn: liveBinding)
                .help("Live metrics refresh about every 2 seconds.")

            if let metrics {
                LabeledContent("CPU", value: cpu(metrics))
                LabeledContent("Memory", value: memory(metrics))
                LabeledContent("Network", value: network(metrics))
                LabeledContent("Block I/O", value: blockIO(metrics))
                if let procs = metrics.numProcesses {
                    LabeledContent("Processes", value: "\(procs)")
                }
            } else {
                Text(isStreaming ? "Waiting for the first sample…" : "No metrics yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var liveBinding: Binding<Bool> {
        Binding(get: { isStreaming }, set: { onToggleLive($0) })
    }

    private func cpu(_ m: ContainerMetrics) -> String {
        m.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—"
    }

    private func memory(_ m: ContainerMetrics) -> String {
        guard let used = m.memoryUsageBytes else { return "—" }
        let usedText = Int64(used).formatted(.byteCount(style: .memory))
        if let pct = m.memoryPercent {
            return String(format: "%@ (%.0f%%)", usedText, pct)
        }
        return usedText
    }

    private func network(_ m: ContainerMetrics) -> String {
        let rx = m.networkRxBytes.map { Int64($0).formatted(.byteCount(style: .memory)) } ?? "—"
        let tx = m.networkTxBytes.map { Int64($0).formatted(.byteCount(style: .memory)) } ?? "—"
        return "↓ \(rx)  ↑ \(tx)"
    }

    private func blockIO(_ m: ContainerMetrics) -> String {
        let r = m.blockReadBytes.map { Int64($0).formatted(.byteCount(style: .memory)) } ?? "—"
        let w = m.blockWriteBytes.map { Int64($0).formatted(.byteCount(style: .memory)) } ?? "—"
        return "R \(r)  W \(w)"
    }
}
