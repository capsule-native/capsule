//
//  ServiceLogsView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  System-service log surface: duration range (5 m / 1 h / 1 d), follow toggle,
//  a persistent empty-is-not-failure banner, and a reused LogsPaneView.

import CapsuleDomain
import SwiftUI

struct ServiceLogsView: View {
    @Bindable var model: LogsModel
    let isRunning: Bool
    @State private var rangeMinutes = 5

    private let ranges: [(String, Int)] = [("5m", 5), ("1h", 60), ("1d", 1440)]

    var body: some View {
        VStack(spacing: 0) {
            banner
            controls
            Divider()
            LogsPaneView(model: model)
                .accessibilityLabel(Text("Service log output", bundle: .module))
        }
        .task { reload() }
        .onDisappear { model.stop() }
    }

    private var banner: some View {
        Label(
            "Empty logs can be normal — some startup modes write only to files, not the unified log.",
            systemImage: "info.circle"
        )
        .font(.callout).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.4))
    }

    private var controls: some View {
        HStack {
            Picker("Window", selection: $rangeMinutes) {
                ForEach(ranges, id: \.1) { Text($0.0).tag($0.1) }
            }
            .pickerStyle(.segmented).fixedSize()
            Spacer()
            Button("Refresh") { reload() }
        }
        .padding(8)
        .disabled(!isRunning)
        .onChange(of: rangeMinutes) { _, _ in reload() }
        .onChange(of: model.follow) { _, _ in reload() }
    }

    private func reload() {
        model.lastMinutes = rangeMinutes
        model.start(id: "")
    }
}
