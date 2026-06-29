# Terminal preference for the "Open in Terminal" handoffs — Design

Status: approved-to-build (user-confirmed the design + the `.command`-open-with mechanism). Date: 2026-06-29.
Branch: `terminal-preference` (cut from `main` at the post-M8 HEAD).

## 1. Goal & scope

Capsule hands a command off to a terminal in two places — the **Open-in-Terminal** button for
exec/run (M7) and the **DNS create/delete** `sudo` handoff (M8). Both write a temporary
`.command` script and call `NSWorkspace.shared.open(url)`, which routes the script to **macOS's
default handler for `.command` files**. That already honors a user who has set their preferred
terminal as the default `.command` app (Finder → Get Info → "Change All…"), but most users who
prefer iTerm/Ghostty/Warp have not changed that obscure association, so the command opens in
Terminal.app.

Add a **Capsule terminal preference** so the user picks the terminal app in-app, independent of
the system `.command` association. One preference governs **both** handoff surfaces.

**Out of scope (YAGNI):** per-terminal launch scripting to *guarantee* auto-run in every
terminal (AppleScript for Terminal/iTerm, `ghostty -e`, etc.). We reuse the existing
`.command` script and open it *with* the chosen app; that reliably runs in `.command`-executing
terminals (Terminal.app, iTerm) and degrades gracefully elsewhere (see §5). Also out of scope:
syncing the choice anywhere, or changing the embedded SwiftTerm terminal.

## 2. Facts (verified against the current code on this machine)

- `Sources/CapsuleApp/AppEnvironment.swift` has two file-scope handoffs, both ending in
  `NSWorkspace.shared.open(url)` on a temp `…/capsule-<uuid>.command` (0o755), swept after 10s:
  - `openCommandInTerminalApp(_ argv:executablePath:)` — script `#!/bin/sh\nexec <cmd>\n`
    (wired into M7's `openInTerminalApp` closure → exec/run "Open in Terminal").
  - `openPrivilegedCommandInTerminalApp(_ argv:executablePath:)` — script
    `#!/bin/sh\nexec sudo <cmd>\n` via the pure `privilegedTerminalScript(_:executablePath:)`
    (wired into M8's `runPrivilegedInTerminal` closure → DNS create/delete).
- `NSWorkspace.shared.open(url)` opens with the default app for the file's type, i.e. the
  user's `.command` handler. `NSWorkspace.open([url], withApplicationAt:configuration:)` opens
  the file *with a specific app*. `NSWorkspace.urlForApplication(withBundleIdentifier:)` returns
  the installed app's URL or nil.
- Known terminal bundle ids: Terminal.app `com.apple.Terminal`, iTerm2 `com.googlecode.iterm2`,
  Ghostty `com.mitchellh.ghostty`, Warp `dev.warp.Warp-Stable`. (Exact ids are best-known; an
  id that doesn't resolve simply falls back to the system default — §4.)

## 3. Components

### 3.1 `TerminalPreference` (pure, `CapsuleDomain`)
```
public enum TerminalPreference: Sendable, Equatable {
    case systemDefault                 // today's behavior (default)
    case terminalApp                   // com.apple.Terminal
    case iTerm                         // com.googlecode.iterm2
    case ghostty                       // com.mitchellh.ghostty
    case warp                          // dev.warp.Warp-Stable
    case custom(appPath: String)       // a chosen .app bundle path

    public var bundleIdentifier: String? { … }   // nil for systemDefault and custom
    public var customAppPath: String? { … }       // non-nil only for custom
}
```
Plus a stable `UserDefaults` string encoding (e.g. `"systemDefault" | "com.apple.Terminal" | … |
"custom:<path>"`) with an `init?(storage:)` / `var storageValue: String`, and the key constant
`"capsule.terminalPreference"`. All pure and unit-testable.

### 3.2 Resolver (`CapsuleApp`)
`func resolveTerminalApp(_ pref: TerminalPreference, lookup: (String) -> URL?, fileExists: (String) -> Bool) -> URL?`
— returns the app URL to open with, or `nil` meaning "use the system default". Logic: `systemDefault`
→ nil; bundle-id cases → `lookup(id)` (nil if not installed → caller falls back); `custom(path)`
→ `URL(fileURLWithPath: path)` if `fileExists`, else nil. `lookup`/`fileExists` are injected so
the function is pure and testable; production passes `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`
and `FileManager.default.fileExists`.

### 3.3 Handoff functions (`CapsuleApp`)
Both `openCommandInTerminalApp` and `openPrivilegedCommandInTerminalApp` gain a
`terminalApp: URL?` parameter (the resolved app, or nil). After writing the `.command`: if
`terminalApp` is non-nil, `NSWorkspace.shared.open([url], withApplicationAt: terminalApp,
configuration: .init())` with a completion handler that, on error, falls back to
`NSWorkspace.shared.open(url)`; if nil, `NSWorkspace.shared.open(url)` as today. The temp-file
sweep is unchanged. The `live()` closures (`openInTerminalApp`, `runPrivilegedInTerminal`) read
the current `TerminalPreference` from `UserDefaults` and resolve it (§3.2) at call time, so a
preference change takes effect on the next handoff with no app restart.

### 3.4 Settings UI (`CapsuleUI`)
A new **General** tab in `PreferencesView` (`Label("General", systemImage: "gearshape")`),
hosting a small `TerminalPreferenceView`: a `Picker` over the built-in cases bound via
`@AppStorage("capsule.terminalPreference")` (through a tiny adapter to/from `storageValue`), a
**Choose…** button (NSOpenPanel limited to `.app`) that sets `custom(path)` and shows the chosen
app's name, and one caption line of guidance (§4). `PreferencesView.init` gains no model
dependency for this (it reads `@AppStorage`); imports stay `CapsuleDomain` + `SwiftUI` +
(for the panel) `AppKit` — all already allowed in `CapsuleUI`.

## 4. Behavior, fallback & copy

- Default is `systemDefault` → byte-for-byte today's behavior; no migration.
- Chosen app not installed / custom path missing / open fails → **silently fall back to the
  system default** `.command` handler (never error, never leave the user stuck — same
  non-fatal philosophy as the existing handoffs).
- Settings caption (honest about the mechanism): *"Capsule opens the command as a `.command`
  script in this app. Terminal and iTerm run it automatically; some terminals may open without
  running it — if so, use System default."*

## 5. Testing

- `TerminalPreferenceTests` (pure): `storageValue`/`init?(storage:)` round-trips for every case
  incl. `custom:<path>`; `bundleIdentifier`/`customAppPath` correctness.
- `resolveTerminalApp` tests (pure, injected `lookup`/`fileExists`): `systemDefault` → nil;
  installed bundle id → its URL; not-installed bundle id → nil (→ fallback); `custom` existing →
  file URL; `custom` missing → nil. The resolver lives in `CapsuleApp`; `CapsuleUnitTests`
  already depends on and imports `CapsuleApp` (`CompositionTests`, `AppEnvironmentActionsTests`),
  so it is directly reachable — make it `public`/internal-testable accordingly.
- The `NSWorkspace` open calls stay IO and untested, exactly like the existing handoffs.
- Close-out: `make ci` green; a quick live check (set the pref to iTerm, trigger Open-in-Terminal
  and a DNS create, confirm it opens in iTerm and runs).

## 6. Acceptance

A General settings tab lets the user pick their terminal (built-ins + Choose…); both the
exec/run Open-in-Terminal handoff and the DNS `sudo` handoff open in the chosen app, taking
effect without restart; an unset/uninstalled/failed choice falls back to the system default
`.command` handler; default behavior is unchanged for users who don't touch the setting.
