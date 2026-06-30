//
//  KernelSetupSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Sheet presented from AdvancedSettingsView: lets the user pick a kernel source, preview the
//  resulting `container system kernel set …` command, and fire the install task.

import AppKit  // NSOpenPanel
import CapsuleDomain
import SwiftUI

struct KernelSetupSheet: View {
    @Bindable var model: KernelManagerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Change Kernel").font(.title3.bold())

            Label(model.recoveryGuidance, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.callout)

            Picker("Source", selection: $model.draft.mode) {
                ForEach(KernelSourceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch model.draft.mode {
            case .recommended:
                Text("Downloads and installs a known-good kernel.")
                    .foregroundStyle(.secondary)

            case .localFile:
                HStack {
                    TextField("Kernel file path", text: $model.draft.binaryPath)
                    Button("Choose…") { chooseFile() }
                }
                archAndForce

            case .remoteTar:
                TextField("Tar archive URL or path", text: $model.draft.tarURL)
                TextField("Archive member (optional)", text: $model.draft.tarMember)
                archAndForce
            }

            Text(model.commandPreview)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.secondary)

            if let msg = model.validationMessage {
                Text(msg).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Install") {
                    model.install()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.validationMessage != nil)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var archAndForce: some View {
        HStack {
            Picker("Architecture", selection: $model.draft.arch) {
                ForEach(KernelManagerModel.archOptions, id: \.self) { archRaw in
                    Text(archRaw).tag(archRaw)
                }
            }
            .fixedSize()
            Toggle("Overwrite existing (--force)", isOn: $model.draft.force)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.draft.binaryPath = url.path
        }
    }
}
