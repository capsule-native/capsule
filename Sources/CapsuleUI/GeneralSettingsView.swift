//
//  GeneralSettingsView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The General preferences pane. Hosts Appearance (Light/Dark/System), interface Language, and
//  the "Open in Terminal" app picker. Each setting is backed by @AppStorage keyed on a pure
//  CapsuleDomain preference type; resolution/application lives in the App/UI layer. Imports only
//  CapsuleDomain + SwiftUI + AppKit (NSOpenPanel / NSWorkspace) — no backend module.

import AppKit
import CapsuleDomain
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(AppearancePreference.storageKey) private var appearanceRaw =
        AppearancePreference.system.storageValue
    @AppStorage(LanguagePreference.storageKey) private var languageRaw =
        LanguagePreference.system.storageValue
    @AppStorage(TerminalPreference.storageKey) private var terminalRaw =
        TerminalPreference.systemDefault.storageValue

    /// True once the user changes the language this session, so we can prompt for a relaunch.
    @State private var languageChanged = false

    private var appearance: Binding<AppearancePreference> {
        Binding(
            get: { AppearancePreference(storage: appearanceRaw) },
            set: { appearanceRaw = $0.storageValue })
    }

    private var language: Binding<LanguagePreference> {
        Binding(
            get: { LanguagePreference(storage: languageRaw) },
            set: { newValue in
                guard newValue.storageValue != languageRaw else { return }
                languageRaw = newValue.storageValue
                applyLanguage(newValue)
                languageChanged = true
            })
    }

    private var terminal: Binding<TerminalPreference> {
        Binding(
            get: { TerminalPreference(storage: terminalRaw) ?? .systemDefault },
            set: { terminalRaw = $0.storageValue })
    }

    var body: some View {
        Form {
            Section {
                Picker(selection: appearance) {
                    Text("System", bundle: .module).tag(AppearancePreference.system)
                    Text("Light", bundle: .module).tag(AppearancePreference.light)
                    Text("Dark", bundle: .module).tag(AppearancePreference.dark)
                } label: {
                    Text("Theme", bundle: .module)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance", bundle: .module)
            }

            Section {
                Picker(selection: language) {
                    Text("System Default", bundle: .module).tag(LanguagePreference.system)
                    ForEach(LanguagePreference.supportedCodes, id: \.self) { code in
                        Text(languageName(code)).tag(LanguagePreference.language(code: code))
                    }
                } label: {
                    Text("Language", bundle: .module)
                }

                if languageChanged {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Changes take effect after you relaunch Capsule.", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button {
                            relaunch()
                        } label: {
                            Text("Relaunch", bundle: .module)
                        }
                    }
                }
            } header: {
                Text("Language", bundle: .module)
            }

            terminalSection
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 460, minHeight: 320, alignment: .topLeading)
    }

    // MARK: Open in Terminal (unchanged behavior, moved from TerminalPreferenceView)

    private var terminalSection: some View {
        Section("Open in Terminal") {
            Picker("Terminal", selection: terminal) {
                Text("System default").tag(TerminalPreference.systemDefault)
                Text("Terminal").tag(TerminalPreference.terminalApp)
                Text("iTerm").tag(TerminalPreference.iTerm)
                Text("Ghostty").tag(TerminalPreference.ghostty)
                Text("Warp").tag(TerminalPreference.warp)
                if case let .custom(path) = terminal.wrappedValue {
                    Text("Custom — \(appName(path))", bundle: .module).tag(
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

    /// The language's own name (autonym), e.g. "Español", "日本語", "简体中文".
    private func languageName(_ code: String) -> String {
        let locale = Locale(identifier: code)
        let name = locale.localizedString(forIdentifier: code) ?? code
        return name.prefix(1).localizedUppercase + name.dropFirst()
    }

    /// Writes the chosen language to the `AppleLanguages` default (or clears it for `.system`).
    /// macOS reads this at launch, so the switch applies after a relaunch.
    private func applyLanguage(_ preference: LanguagePreference) {
        switch preference {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case let .language(code):
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }

    /// Opens a fresh instance of the app and quits this one, so the language change takes hold.
    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL, configuration: configuration
        ) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
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
            terminalRaw = TerminalPreference.custom(appPath: url.path).storageValue
        }
    }
}
