//
//  CreateMachineSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Create-machine wizard: image preset/custom picker, resources (CPUs/memory/home-mount),
//  an Advanced disclosure (name, set-default, no-boot, arch/OS/platform), explanatory copy
//  for first-boot provisioning and persistent-home semantics, a live command preview, and
//  Cancel/Create buttons. Mirrors the shape of CreateNetworkSheet; never imports CapsuleBackend.

import CapsuleDomain
import SwiftUI

struct CreateMachineSheet: View {
    let actions: MachineActionsModel
    let onClose: () -> Void

    @State private var draft = MachineDraft()
    @State private var busy = false
    @State private var useCustomImage = false
    @State private var imageSelection: String = MachineImagePreset.all[0].reference

    private static let customImageTag = "__custom__"

    private var canCreate: Bool {
        actions.canCreate(draft) && !busy
    }

    private var homeMountDisplay: String {
        switch draft.homeMount {
        case "rw": return "read-write"
        case "ro": return "read-only"
        case "none": return "not mounted"
        default: return draft.homeMount
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Create Machine", systemImage: "desktopcomputer")
                .font(.headline)

            Form {
                // MARK: Image

                Picker("Image", selection: $imageSelection) {
                    ForEach(MachineImagePreset.all) { preset in
                        Text(verbatim: preset.displayName).tag(preset.reference)
                    }
                    Text("Custom\u{2026}").tag(Self.customImageTag)
                }
                .onChange(of: imageSelection) { _, selection in
                    if selection == Self.customImageTag {
                        useCustomImage = true
                        draft.image = ""
                    } else {
                        useCustomImage = false
                        draft.image = selection
                    }
                }

                if useCustomImage {
                    TextField(
                        "Image reference", text: $draft.image,
                        prompt: Text("e.g. ubuntu:24.04"))
                }

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

                // MARK: Advanced

                AdvancedDisclosure {
                    TextField("Name (optional)", text: $draft.name)
                    Toggle("Set as default", isOn: $draft.setDefault)
                    Toggle("Create without booting", isOn: $draft.noBoot)
                    TextField("Arch", text: $draft.arch, prompt: Text("arm64"))
                    TextField("OS", text: $draft.os, prompt: Text("linux"))
                    TextField("Platform", text: $draft.platform)
                }

                // MARK: Explanatory copy

                Text(
                    "The first boot downloads the image and provisions a persistent Linux environment. This can take several minutes."
                )
                .font(.caption).foregroundStyle(.secondary)

                Text(
                    "Your home directory will be mounted \(homeMountDisplay). Files inside the machine persist across stops; deleting the machine erases them."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .onAppear { draft.image = imageSelection }

            // MARK: Command preview

            CommandPreviewView(actions.commandInvocation(for: draft))

            // MARK: Buttons

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
            let ok = await actions.create(draft: draft)
            busy = false
            if ok { onClose() }
        }
    }
}
