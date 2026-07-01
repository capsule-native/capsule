//
//  CreateVolumeSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Create Volume sheet: a required Name field, an "Advanced Options" disclosure (size,
//  driver --opt rows, label rows), and a live `container volume create …` command preview.
//  Low-risk, so there is no confirmation; Create is disabled until the draft validates.
//
//  This view imports only CapsuleDomain + SwiftUI and consumes only Domain primitives: the
//  command-preview String, the validity accessors, and the draft-taking create on
//  VolumeActionsModel. It never names a backend Configuration type — mirroring how QuickRunSheet
//  and BuildSheet are backed by RunModel/BuildModel.

import CapsuleDomain
import SwiftUI

struct CreateVolumeSheet: View {
    let actions: VolumeActionsModel
    var onClose: () -> Void

    @State private var draft = VolumeDraft()
    @State private var showAdvanced = false
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Create Volume", systemImage: "externaldrive.badge.plus")
                .font(.headline)

            labeledField("Name (required)", text: $draft.name, prompt: "data")

            AdvancedDisclosure("Advanced Options", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    labeledField("Size", text: $draft.size, prompt: "10G")
                    keyValueEditor(
                        "Driver options (--opt)", rows: $draft.options,
                        keyPrompt: "journaling", valuePrompt: "on")
                    keyValueEditor(
                        "Labels (--label)", rows: $draft.labels,
                        keyPrompt: "env", valuePrompt: "dev")
                }
                .padding(.top, 6)
            }

            commandPreview

            if !draft.name.isEmpty, let message = actions.validationMessage(draft) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Cancel", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isCreating || !actions.isValid(draft))
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var commandPreview: some View {
        CommandPreviewView(actions.commandInvocation(for: draft))
    }

    private func create() {
        isCreating = true
        Task {
            let ok = await actions.create(draft: draft)
            isCreating = false
            if ok { onClose() }
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
        }
    }

    private func keyValueEditor(
        _ label: String, rows: Binding<[KeyValueRow]>, keyPrompt: String, valuePrompt: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    rows.wrappedValue.append(KeyValueRow())
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help("Add a row")
            }
            ForEach(rows.wrappedValue.indices, id: \.self) { index in
                HStack {
                    TextField(keyPrompt, text: rows[index].key)
                        .textFieldStyle(.roundedBorder)
                    Text("=").foregroundStyle(.secondary)
                    TextField(valuePrompt, text: rows[index].value)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        rows.wrappedValue.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}
