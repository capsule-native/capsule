# Terminal Preference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user pick which terminal app Capsule's "Open in Terminal" (exec/run) and DNS `sudo` handoffs open in, defaulting to today's behavior.

**Architecture:** A pure `TerminalPreference` enum (CapsuleDomain) persisted in `UserDefaults`; a pure, injectable `resolveTerminalApp` resolver (CapsuleApp) that maps the preference to an installed app URL or `nil`; the two existing `*InTerminalApp` handoffs open the temp `.command` *with* that app (falling back to the system `.command` handler); a new **General** settings tab (CapsuleUI) drives the preference via `@AppStorage`.

**Tech Stack:** Swift, SwiftUI + `@AppStorage`, AppKit `NSWorkspace`/`NSOpenPanel`, XCTest. SwiftPM modules + XcodeGen app target.

Design spec: `docs/superpowers/specs/2026-06-29-terminal-preference-design.md`.

## Global Constraints

- **Layering (arch-guard `make arch`):** `CapsuleDomain` imports no UI, no `Foundation.Process` (it may import `Foundation`). `CapsuleApp` is the composition root (may use AppKit). `CapsuleUI` may import `AppKit` (for `NSOpenPanel`) + `SwiftUI` + `CapsuleDomain`, but NOT `CapsuleBackend`/`CapsuleCLIBackend`.
- **Default is `systemDefault`** → byte-for-byte today's behavior; no migration, no behavior change unless the user opts in.
- **Never error on a bad choice:** an unset / not-installed / failed terminal choice silently falls back to `NSWorkspace.shared.open(url)` (the system `.command` handler) — same non-fatal philosophy as the existing handoffs.
- **One UserDefaults key:** `TerminalPreference.storageKey == "capsule.terminalPreference"`, shared by the UI (`@AppStorage`) and the handoff read.
- **Build/test:** `make test` (= `swift test`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` exported); focused: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter <Class>`; `make check` (lint+arch+headers); full gate `make ci`. SwiftUI views have no unit tests (repo convention) — verified by `make build` + `make check`.
- **Every new Swift file** starts with the standard license header (copy from a sibling). Run `make format` before committing. Commit messages end with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` then `Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he`.
- **TDD** for Tasks 1–2 (pure logic). Frequent commits. DRY, YAGNI.

---

### Task 1: `TerminalPreference` enum + UserDefaults encoding (pure)

**Files:**
- Create: `Sources/CapsuleDomain/TerminalPreference.swift`
- Test: `Tests/CapsuleUnitTests/TerminalPreferenceTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public enum TerminalPreference: Sendable, Equatable, Hashable` with cases `systemDefault, terminalApp, iTerm, ghostty, warp, custom(appPath: String)`; `static let storageKey = "capsule.terminalPreference"`; `var bundleIdentifier: String?`; `var customAppPath: String?`; `var storageValue: String`; `init?(storage: String)`. Consumed by Tasks 2–4.

- [ ] **Step 1: Write the failing tests** at `Tests/CapsuleUnitTests/TerminalPreferenceTests.swift`:
```swift
//
//  TerminalPreferenceTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class TerminalPreferenceTests: XCTestCase {
    private let all: [TerminalPreference] = [
        .systemDefault, .terminalApp, .iTerm, .ghostty, .warp, .custom(appPath: "/Applications/Foo.app"),
    ]

    func testStorageRoundTrips() {
        for pref in all {
            XCTAssertEqual(TerminalPreference(storage: pref.storageValue), pref, "round-trip \(pref)")
        }
    }

    func testBundleIdentifiers() {
        XCTAssertEqual(TerminalPreference.terminalApp.bundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(TerminalPreference.iTerm.bundleIdentifier, "com.googlecode.iterm2")
        XCTAssertEqual(TerminalPreference.ghostty.bundleIdentifier, "com.mitchellh.ghostty")
        XCTAssertEqual(TerminalPreference.warp.bundleIdentifier, "dev.warp.Warp-Stable")
        XCTAssertNil(TerminalPreference.systemDefault.bundleIdentifier)
        XCTAssertNil(TerminalPreference.custom(appPath: "/x").bundleIdentifier)
    }

    func testCustomAppPath() {
        XCTAssertEqual(TerminalPreference.custom(appPath: "/Applications/Foo.app").customAppPath, "/Applications/Foo.app")
        XCTAssertNil(TerminalPreference.terminalApp.customAppPath)
    }

    func testInitFromGarbageIsNil() {
        XCTAssertNil(TerminalPreference(storage: "nonsense"))
        XCTAssertNil(TerminalPreference(storage: ""))
    }

    func testCustomStorageValueFormat() {
        XCTAssertEqual(TerminalPreference.custom(appPath: "/Applications/Foo.app").storageValue, "custom:/Applications/Foo.app")
    }
}
```

- [ ] **Step 2: Run; expect FAIL.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter TerminalPreferenceTests` → build error: `cannot find type 'TerminalPreference' in scope`.

- [ ] **Step 3: Implement** `Sources/CapsuleDomain/TerminalPreference.swift`:
```swift
//
//  TerminalPreference.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Which terminal app
//  Capsule opens for the "Open in Terminal" + DNS sudo handoffs. Pure value type; the App layer
//  resolves it to an installed app, the UI edits it via @AppStorage(TerminalPreference.storageKey).

public enum TerminalPreference: Sendable, Equatable, Hashable {
    case systemDefault
    case terminalApp
    case iTerm
    case ghostty
    case warp
    case custom(appPath: String)

    /// The single UserDefaults key shared by the settings UI and the handoff read.
    public static let storageKey = "capsule.terminalPreference"

    /// The app's bundle identifier, or nil for `systemDefault` (no specific app) and `custom`
    /// (identified by a path, not an id).
    public var bundleIdentifier: String? {
        switch self {
        case .terminalApp: return "com.apple.Terminal"
        case .iTerm: return "com.googlecode.iterm2"
        case .ghostty: return "com.mitchellh.ghostty"
        case .warp: return "dev.warp.Warp-Stable"
        case .systemDefault, .custom: return nil
        }
    }

    public var customAppPath: String? {
        if case let .custom(path) = self { return path }
        return nil
    }

    /// Stable string for UserDefaults.
    public var storageValue: String {
        switch self {
        case .systemDefault: return "systemDefault"
        case .terminalApp: return "com.apple.Terminal"
        case .iTerm: return "com.googlecode.iterm2"
        case .ghostty: return "com.mitchellh.ghostty"
        case .warp: return "dev.warp.Warp-Stable"
        case let .custom(path): return "custom:\(path)"
        }
    }

    public init?(storage: String) {
        switch storage {
        case "systemDefault": self = .systemDefault
        case "com.apple.Terminal": self = .terminalApp
        case "com.googlecode.iterm2": self = .iTerm
        case "com.mitchellh.ghostty": self = .ghostty
        case "dev.warp.Warp-Stable": self = .warp
        default:
            let prefix = "custom:"
            guard storage.hasPrefix(prefix) else { return nil }
            self = .custom(appPath: String(storage.dropFirst(prefix.count)))
        }
    }
}
```

- [ ] **Step 4: Run; expect PASS.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter TerminalPreferenceTests` → all pass. Then `make format`.

- [ ] **Step 5: Commit.**
```bash
git add Sources/CapsuleDomain/TerminalPreference.swift Tests/CapsuleUnitTests/TerminalPreferenceTests.swift
git commit -m "feat: TerminalPreference enum + UserDefaults encoding

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 2: `resolveTerminalApp` resolver (pure, injectable)

**Files:**
- Create: `Sources/CapsuleApp/TerminalLauncher.swift`
- Test: `Tests/CapsuleUnitTests/TerminalLauncherTests.swift`

**Interfaces:**
- Consumes (Task 1): `TerminalPreference`, `.bundleIdentifier`, `.customAppPath`.
- Produces: `public func resolveTerminalApp(_ preference: TerminalPreference, lookup: (String) -> URL?, fileExists: (String) -> Bool) -> URL?` — the app to open the `.command` with, or `nil` meaning "use the system default handler". Consumed by Task 3.

- [ ] **Step 1: Write the failing tests** at `Tests/CapsuleUnitTests/TerminalLauncherTests.swift`:
```swift
//
//  TerminalLauncherTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation
import XCTest

import CapsuleApp
import CapsuleDomain

final class TerminalLauncherTests: XCTestCase {
    private let iTermURL = URL(fileURLWithPath: "/Applications/iTerm.app")

    func testSystemDefaultResolvesToNil() {
        XCTAssertNil(resolveTerminalApp(.systemDefault, lookup: { _ in self.iTermURL }, fileExists: { _ in true }))
    }

    func testInstalledBundleIDResolvesToItsURL() {
        let url = resolveTerminalApp(
            .iTerm,
            lookup: { $0 == "com.googlecode.iterm2" ? self.iTermURL : nil },
            fileExists: { _ in true })
        XCTAssertEqual(url, iTermURL)
    }

    func testNotInstalledBundleIDResolvesToNil() {
        XCTAssertNil(resolveTerminalApp(.ghostty, lookup: { _ in nil }, fileExists: { _ in true }))
    }

    func testCustomExistingPathResolvesToFileURL() {
        let url = resolveTerminalApp(
            .custom(appPath: "/Applications/Foo.app"),
            lookup: { _ in nil },
            fileExists: { $0 == "/Applications/Foo.app" })
        XCTAssertEqual(url, URL(fileURLWithPath: "/Applications/Foo.app"))
    }

    func testCustomMissingPathResolvesToNil() {
        XCTAssertNil(resolveTerminalApp(.custom(appPath: "/nope.app"), lookup: { _ in nil }, fileExists: { _ in false }))
    }
}
```

- [ ] **Step 2: Run; expect FAIL.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter TerminalLauncherTests` → `cannot find 'resolveTerminalApp' in scope`.

- [ ] **Step 3: Implement** `Sources/CapsuleApp/TerminalLauncher.swift`:
```swift
//
//  TerminalLauncher.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Resolves a TerminalPreference to the app the handoff should open the `.command` with, or nil
//  ("use the system default `.command` handler"). Pure + injectable so it is unit-testable;
//  production wires `lookup`/`fileExists` to NSWorkspace/FileManager.

import CapsuleDomain
import Foundation

public func resolveTerminalApp(
    _ preference: TerminalPreference,
    lookup: (String) -> URL?,
    fileExists: (String) -> Bool
) -> URL? {
    switch preference {
    case .systemDefault:
        return nil
    case .terminalApp, .iTerm, .ghostty, .warp:
        guard let identifier = preference.bundleIdentifier else { return nil }
        return lookup(identifier)
    case let .custom(appPath):
        return fileExists(appPath) ? URL(fileURLWithPath: appPath) : nil
    }
}
```

- [ ] **Step 4: Run; expect PASS.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter TerminalLauncherTests` → all pass. `make format`.

- [ ] **Step 5: Commit.**
```bash
git add Sources/CapsuleApp/TerminalLauncher.swift Tests/CapsuleUnitTests/TerminalLauncherTests.swift
git commit -m "feat: resolveTerminalApp preference resolver (pure, injectable)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 3: Honor the preference in both handoffs (AppEnvironment)

**Files:**
- Modify: `Sources/CapsuleApp/AppEnvironment.swift` (the two `*InTerminalApp` funcs ~288 & ~326; the `openInTerminalApp`/`runPrivilegedInTerminal` closures in `live()` ~163–170)

**Interfaces:**
- Consumes (Tasks 1–2): `TerminalPreference(storage:)`, `TerminalPreference.storageKey`, `resolveTerminalApp(_:lookup:fileExists:)`.
- Produces: both handoffs open the `.command` with the resolved terminal app (system-default fallback). No new public API.

This task changes shared composition-root code; there is no view/IO unit test (consistent with the existing handoffs). It is verified by `make build` + `make check` + the Task 1–2 tests staying green. The two `*InTerminalApp` functions currently duplicate the write/open/sweep; extract that into one `openScriptInTerminal(_:terminalApp:)` helper to hold the new open-with-app + fallback logic once.

- [ ] **Step 1: Add the shared opener helper.** In `Sources/CapsuleApp/AppEnvironment.swift`, immediately BEFORE `func openCommandInTerminalApp(`, insert:
```swift
/// Writes `script` to a throwaway `.command` and opens it: with `terminalApp` when set
/// (falling back to the system `.command` handler if that open errors), else with the system
/// handler directly. Sweeps the temp file after 10s. Non-fatal on any failure.
// File-scope, NOT @MainActor — matches the existing `open*InTerminalApp` functions, which
// compile un-annotated in this module (Swift 5 concurrency mode). Do not add @MainActor.
private func openScriptInTerminal(_ script: String, terminalApp: URL?) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("capsule-\(UUID().uuidString).command")
    do {
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        if let terminalApp {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: terminalApp, configuration: configuration) {
                _, error in
                if error != nil {
                    // Chosen app couldn't open it — fall back to the default `.command` handler.
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            NSWorkspace.shared.open(url)
        }
        Task {
            try? await Task.sleep(for: .seconds(10))
            try? FileManager.default.removeItem(at: url)
        }
    } catch {
        // Non-fatal: the embedded terminal / manual run remains available.
    }
}
```

- [ ] **Step 2: Route both handoffs through it + add the `terminalApp` parameter.** Replace the body of `openCommandInTerminalApp` so it reads:
```swift
func openCommandInTerminalApp(_ argv: [String], executablePath: String, terminalApp: URL?) {
    guard !argv.isEmpty else { return }
    let resolved = argv.enumerated().map { index, token in
        index == 0 && token == "container" ? executablePath : token
    }
    let command = resolved.map(shellQuote).joined(separator: " ")
    openScriptInTerminal("#!/bin/sh\nexec \(command)\n", terminalApp: terminalApp)
}
```
and replace the body of `openPrivilegedCommandInTerminalApp` so it reads:
```swift
func openPrivilegedCommandInTerminalApp(_ argv: [String], executablePath: String, terminalApp: URL?) {
    guard !argv.isEmpty else { return }
    openScriptInTerminal(privilegedTerminalScript(argv, executablePath: executablePath), terminalApp: terminalApp)
}
```
(Both functions lose their own temp-file/`NSWorkspace`/sweep blocks — that logic now lives only in `openScriptInTerminal`. `privilegedTerminalScript` is unchanged.)

- [ ] **Step 3: Resolve the preference in the `live()` closures.** In `live()`, replace the `openInTerminalApp` and `runPrivilegedInTerminal` closures (~163–170) with:
```swift
        let openInTerminalApp: @MainActor ([String]) -> Void = { argv in
            let app = currentTerminalApp()
            openCommandInTerminalApp(argv, executablePath: cliBackend.executableURL.path, terminalApp: app)
            shell.appendActivity("Opened in Terminal: \(argv.joined(separator: " "))")
        }
        let runPrivilegedInTerminal: @MainActor ([String]) -> Void = { argv in
            let app = currentTerminalApp()
            openPrivilegedCommandInTerminalApp(
                argv, executablePath: cliBackend.executableURL.path, terminalApp: app)
            shell.appendActivity("Opened in Terminal (sudo): \(argv.joined(separator: " "))")
        }
```

- [ ] **Step 4: Add the `currentTerminalApp` resolver-at-call-time helper.** Insert it right after `openScriptInTerminal` (still file-scope in `AppEnvironment.swift`):
```swift
/// Reads the saved TerminalPreference and resolves it to an installed app URL (or nil for the
/// system default) at call time, so a settings change takes effect on the next handoff.
/// (File-scope, not @MainActor — matches the existing handoff functions in this module.)
private func currentTerminalApp() -> URL? {
    let raw = UserDefaults.standard.string(forKey: TerminalPreference.storageKey) ?? ""
    let preference = TerminalPreference(storage: raw) ?? .systemDefault
    return resolveTerminalApp(
        preference,
        lookup: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        fileExists: { FileManager.default.fileExists(atPath: $0) })
}
```

- [ ] **Step 5: Build + checks.** `make build` → succeeds. `make check` → arch ✅ + lint + headers clean. `make test` → full suite green (no regressions; AppEnvironment composition tests still pass). Run `make format` first if lint flags formatting.
  Expected: build succeeds; the only call sites of the two functions are the two closures just updated.

- [ ] **Step 6: Commit.**
```bash
git add Sources/CapsuleApp/AppEnvironment.swift
git commit -m "feat: open the Terminal handoffs in the user's chosen terminal

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 4: General settings tab + `TerminalPreferenceView`

**Files:**
- Create: `Sources/CapsuleUI/TerminalPreferenceView.swift`
- Modify: `Sources/CapsuleUI/PreferencesView.swift` (add the General tab to the `TabView` in `body`)

**Interfaces:**
- Consumes (Task 1): `TerminalPreference`, `.storageKey`, `.storageValue`, `init?(storage:)`, `.custom(appPath:)`.
- Produces: `struct TerminalPreferenceView: View` (no init args; reads `@AppStorage`). The Settings window gains a **General** tab.

SwiftUI view — no unit test (repo convention). Verified by `make build` + `make check`.

- [ ] **Step 1: Create the view** `Sources/CapsuleUI/TerminalPreferenceView.swift`:
```swift
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
                        Text("Custom — \(appName(path))").tag(TerminalPreference.custom(appPath: path))
                    }
                }

                HStack {
                    Button("Choose…", action: chooseApp)
                    Spacer()
                }

                Text(
                    "Capsule opens the command as a .command script in this app. Terminal and iTerm "
                        + "run it automatically; some terminals may open without running it — if so, "
                        + "use System default.")
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
```

- [ ] **Step 2: Add the General tab** in `Sources/CapsuleUI/PreferencesView.swift` — make `body`'s `TabView` read (General first; Registries/Networking unchanged):
```swift
    public var body: some View {
        TabView {
            TerminalPreferenceView()
                .tabItem { Label("General", systemImage: "gearshape") }
            RegistriesView(model: registriesModel)
                .tabItem { Label("Registries", systemImage: "person.badge.key") }
            NetworkingView(model: dnsModel)
                .disabled(!systemHealth.supports(.networks))
                .tabItem { Label("Networking", systemImage: "network") }
        }
        .frame(width: 520, height: 420)
    }
```
(Do not change `PreferencesView.init` — `TerminalPreferenceView` reads `@AppStorage` itself, no model needed.)

- [ ] **Step 3: Build + checks.** `make format`, then `make build` → succeeds; `make check` → arch ✅ (CapsuleUI imports only AppKit/CapsuleDomain/SwiftUI here) + lint + headers clean; `make test` → green.

- [ ] **Step 4: Commit.**
```bash
git add Sources/CapsuleUI/TerminalPreferenceView.swift Sources/CapsuleUI/PreferencesView.swift
git commit -m "feat: General settings tab to pick the Open-in-Terminal app

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

## Close-out

- [ ] `make ci` green over the whole branch.
- [ ] Quick live check: build/launch the app (`make run`), Settings → General → pick a terminal you have installed (e.g. iTerm); trigger an exec/run **Open in Terminal** and a **DNS create**, confirm both open in that app and run the command; set it back to System default and confirm the `.command`-handler path still works.
