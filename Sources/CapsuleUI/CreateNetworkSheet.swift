//
//  CreateNetworkSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Create a network: a required Name and an optional Subnet (with a CIDR hint and live
//  conflict validation), plus an Advanced Options disclosure (IPv6 subnet, Internal toggle,
//  plugin, --option and --label rows). A live command preview shows the exact argv. Low
//  risk, so no confirmation. The sheet never names the backend NetworkConfiguration and never
//  calls the validator directly — it speaks only to NetworkActionsModel (commandPreview,
//  subnetConflictMessage, canCreate, create(draft:against:)).

import CapsuleDomain
import SwiftUI

struct CreateNetworkSheet: View {
    let actions: NetworkActionsModel
    let existingNetworks: [Network]
    let onClose: () -> Void

    @State private var draft = NetworkDraft()
    @State private var busy = false

    /// Live subnet-conflict message (nil = clear), sourced from the model's validity accessor
    /// so the sheet never names NetworkConfiguration nor calls NetworkValidation directly.
    private var subnetConflict: String? {
        actions.subnetConflictMessage(for: draft, against: existingNetworks)
    }

    private var canCreate: Bool {
        actions.canCreate(draft, against: existingNetworks) && !busy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Create Network", systemImage: "network")
                .font(.headline)

            Form {
                TextField("Name", text: $draft.name, prompt: Text("e.g. app-net"))

                VStack(alignment: .leading, spacing: 2) {
                    TextField(
                        "Subnet (optional)", text: $draft.subnet,
                        prompt: Text("e.g. 10.0.0.0/24"))
                    if let conflict = subnetConflict {
                        Text(conflict)
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Leave blank to let the runtime assign a subnet.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                AdvancedDisclosure("Advanced Options") {
                    TextField("IPv6 subnet", text: $draft.subnetV6, prompt: Text("e.g. fd00::/64"))
                    Toggle("Internal (no external connectivity)", isOn: $draft.isInternal)
                    TextField(
                        "Plugin", text: $draft.plugin,
                        prompt: Text("container-network-vmnet"))
                    keyValueEditor("Options (--option)", rows: $draft.options)
                    keyValueEditor("Labels (--label)", rows: $draft.labels)
                }
            }
            .formStyle(.grouped)

            CommandPreviewView(actions.commandInvocation(for: draft))

            HStack {
                Button("Cancel", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func create() {
        busy = true
        Task {
            let ok = await actions.create(draft: draft, against: existingNetworks)
            busy = false
            if ok { onClose() }
        }
    }

    /// A dynamic editor for `key=value` rows (used for both `--option` and `--label`).
    private func keyValueEditor(
        _ label: String, rows: Binding<[KeyValueRow]>
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
                .accessibilityLabel(Text("Add row", bundle: .module))
                .help(Text("Add a \(label.lowercased()) row", bundle: .module))
            }
            ForEach(rows) { $row in
                HStack {
                    TextField("key", text: $row.key).textFieldStyle(.roundedBorder)
                    Text("=").foregroundStyle(.secondary)
                    TextField("value", text: $row.value).textFieldStyle(.roundedBorder)
                    Button {
                        rows.wrappedValue.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Remove row", bundle: .module))
                }
            }
        }
    }
}
