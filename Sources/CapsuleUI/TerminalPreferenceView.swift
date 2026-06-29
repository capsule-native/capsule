//
//  TerminalPreferenceView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The General preferences pane: pick which terminal the "Open in Terminal" + DNS sudo handoffs
//  use. Backed by @AppStorage(TerminalPreference.storageKey); resolution + fallback live in the
//  App layer. Imports only CapsuleDomain + SwiftUI + AppKit (NSOpenPanel) — no backend module.

import AppKit
import CapsuleDomain
import SwiftUI

struct TerminalPreferenceView: View {
    @AppStorage(TerminalPreference.storageKey) private var raw: String =
        TerminalPreference.systemDefault.storageValue

    private var preference: Binding<TerminalPreference> {
        Binding(
            get: { TerminalPreference(storage: raw) ?? .systemDefault },
            set: { raw = $0.storageValue })
    }

    var body: some View {
        Form {
            Section("Open in Terminal") {
                Picker("Terminal", selection: preference) {
                    Text("System default").tag(TerminalPreference.systemDefault)
                    Text("Terminal").tag(TerminalPreference.terminalApp)
                    Text("iTerm").tag(TerminalPreference.iTerm)
                    Text("Ghostty").tag(TerminalPreference.ghostty)
                    Text("Warp").tag(TerminalPreference.warp)
                    if case let .custom(path) = preference.wrappedValue {
                        Text("Custom — \(appName(path))").tag(
                            TerminalPreference.custom(appPath: path))
                    }
                }

                HStack {
                    Button("Choose…", action: chooseApp)
                    Spacer()
                }

                Text(
                    "Capsule opens the command as a .command script in this app. Terminal and iTerm "
                        + "run it automatically; some terminals may open without running it — if so, "
                        + "use System default."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 460, minHeight: 220, alignment: .topLeading)
    }

    private func appName(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            raw = TerminalPreference.custom(appPath: url.path).storageValue
        }
    }
}
