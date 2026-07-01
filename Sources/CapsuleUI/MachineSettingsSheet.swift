//
//  MachineSettingsSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Settings form for an existing machine: CPUs, Memory, Home-mount picker, a prominent
//  restart-required note, a live command preview, and Cancel / Save buttons. Never imports
//  CapsuleBackend.

import CapsuleDomain
import SwiftUI

struct MachineSettingsSheet: View {
    let actions: MachineActionsModel
    let machine: Machine
    let onClose: () -> Void

    @State private var draft: MachineSettingsDraft
    @State private var busy = false

    init(actions: MachineActionsModel, machine: Machine, onClose: @escaping () -> Void) {
        self.actions = actions
        self.machine = machine
        self.onClose = onClose
        _draft = State(initialValue: MachineSettingsDraft(machine: machine))
    }

    private var saveDisabled: Bool {
        actions.settingsProblem(draft) != nil || busy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Machine Settings — \(machine.name)", systemImage: "gearshape")
                .font(.headline)

            Form {
                // MARK: Resources

                TextField(
                    "CPUs (optional)", text: $draft.cpus,
                    prompt: Text("e.g. 4"))
                TextField(
                    "Memory (optional)", text: $draft.memory,
                    prompt: Text("e.g. 8G"))
                Picker("Home mount", selection: $draft.homeMount) {
                    Text("Read-write").tag("rw")
                    Text("Read-only").tag("ro")
                    Text("None").tag("none")
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)

            // MARK: Restart note

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                Text("Changes take effect after the machine restarts.")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // MARK: Command preview

            CommandPreviewView(actions.settingsInvocation(name: machine.name, draft: draft))

            // MARK: Buttons

            HStack {
                Button("Cancel", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saveDisabled)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func save() {
        busy = true
        Task {
            let ok = await actions.apply(settings: draft, to: machine.name)
            busy = false
            if ok { onClose() }
        }
    }
}
