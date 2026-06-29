//
//  MachineLogsView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  A sheet presenting machine logs split into Boot log and Session log sub-tabs.
//  Both LogsModel instances are supplied by MachineActionsModel.makeLogsModels()
//  so that CapsuleUI never needs to import CapsuleBackend.

import CapsuleDomain
import SwiftUI

struct MachineLogsView: View {
    let name: String
    let bootModel: LogsModel
    let sessionModel: LogsModel
    let onClose: () -> Void

    private enum LogTab: Hashable { case boot, session }
    @State private var selectedTab: LogTab = .boot

    init(
        name: String,
        models: (boot: LogsModel, session: LogsModel),
        onClose: @escaping () -> Void
    ) {
        self.name = name
        self.bootModel = models.boot
        self.sessionModel = models.session
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabPane
        }
        .frame(minWidth: 700, minHeight: 420)
        .task {
            bootModel.start(id: name)
            sessionModel.start(id: name)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Picker("Log type", selection: $selectedTab) {
                Text("Boot log").tag(LogTab.boot)
                Text("Session log").tag(LogTab.session)
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
            Spacer()
            Button("Done") { onClose() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Pane

    @ViewBuilder
    private var tabPane: some View {
        switch selectedTab {
        case .boot:
            LogsPaneView(model: bootModel, onOpenInWindow: nil)
        case .session:
            LogsPaneView(model: sessionModel, onOpenInWindow: nil)
        }
    }
}
