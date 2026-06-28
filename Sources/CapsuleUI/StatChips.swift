//
//  StatChips.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Compact per-row CPU/memory chips for the containers Table. Binds to the domain
//  `ContainerMetrics`; renders a muted placeholder when no sample is available.

import CapsuleDomain
import SwiftUI

struct StatChips: View {
    let metrics: ContainerMetrics?

    var body: some View {
        HStack(spacing: 6) {
            chip(systemImage: "cpu", text: cpuText)
            chip(systemImage: "memorychip", text: memoryText)
        }
    }

    private func chip(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }

    private var cpuText: String {
        guard let cpu = metrics?.cpuPercent else { return "—" }
        return String(format: "%.0f%%", cpu)
    }

    private var memoryText: String {
        guard let bytes = metrics?.memoryUsageBytes else { return "—" }
        return Int64(bytes).formatted(.byteCount(style: .memory))
    }
}
