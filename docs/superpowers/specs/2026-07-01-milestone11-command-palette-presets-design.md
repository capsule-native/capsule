# Milestone 11 · Command palette, raw command preview, presets & passthrough — Design

**Date:** 2026-07-01
**Branch:** `milestone-11-command-palette-presets`
**Phase:** 4 (Power-user layer), following Phase 3 (M10 System surface, M9 Machines, M8 Volumes/Networks/DNS).

## Goal

Make Capsule a power tool experts stay inside without losing control:

1. **Command palette** (⌘K) exposing at least: Run selected image; Exec shell in selected
   container; Follow logs; Build from current folder; Pull image; Copy file to container;
   Export container; Start/Stop services; Open system logs; Reclaim disk space; Toggle
   inspector; Open raw command preview.
2. **Menu-bar commands** mirroring every palette action (the menu bar is where macOS users
   expect commands).
3. **Raw command preview** on every task sheet and action — the exact CLI invocation Capsule
   *will run* (or *just ran*), copyable, generated from the **real argument builder** (M2),
   never a hand-written approximation.
4. **Saved Run/Build presets** — save a configured Run or Build sheet as a named preset, edit
   it, and re-invoke it from the palette and menus.
5. **Terminal passthrough** — any command can be escalated into the integrated/detached
   terminal, and **plugin** subcommands (available when the system service is running) get a
   terminal route when there is no first-class UI.
6. **Tiered-complexity pattern, applied consistently** — common controls visible by default,
   advanced flags behind disclosure, raw preview mirroring the exact invocation, terminal
   fallback for the rest.

## Ground truth (probed live 2026-07-01 + subsystem maps)

### The real `container` CLI plugin model

`container --help` enumerates the full built-in subcommand surface (containers: copy/create/
delete/exec/export/inspect/kill/list/logs/run/start/stats/stop/prune; images: build/image/
registry; machine; volume; builder; network; system). **Unknown subcommands are resolved as
external plugin binaries**: `container <name>` looks for `container-<name>` under

```
/usr/local/libexec/container-plugins/
/usr/local/libexec/container/plugins/
```

and the resolver's own error explicitly names those two paths. Plugins require the system
service running. **Discovery is therefore a directory scan, not stdout/help parsing** — robust
and cheap. `builder` is a built-in (not a plugin) with only `builderStatus` wired in Capsule
today; per the resolved scope it is reachable via the generic passthrough but gets **no**
dedicated terminal route (we chose discovery-only).

### Argument-builder subsystem (the preview source of truth)

- Two argv sources exist on opposite sides of the architecture boundary:
  - **`*Configuration.arguments`** (`RunConfiguration`, `BuildConfiguration`,
    `MachineConfiguration`/`MachineSettings`, `VolumeConfiguration`, `NetworkConfiguration`,
    `DNSConfiguration`, `KernelConfiguration`) live in **`CapsuleBackend`** (the port) and are
    already importable from Domain/UI — the existing `commandPreview` accessors read them.
  - **`CLICommand` + `ArgumentBuilder`** live in **`CapsuleCLIBackend`** (the adapter, *above*
    the Domain/UI boundary). They are the only place argv for the non-config ops (list/inspect/
    start/stop/kill/stats/pull/push/save/load/tag/prune/copy/export/exec/logs/registry/system…)
    is assembled. Each `CLICommand.*` is `static func … -> [String]`, excluding the executable.
- The runner (`CLIProcessRunner`) owns the absolute `executableURL` and is the **only**
  `Foundation.Process` user (enforced by `ArchitectureGuardTests`). `commandDescription`
  exists only as ad-hoc `joined(" ")` for error messages — there is **no** executable-aware
  command value type.
- `SecretRedactor` lives in `CapsuleDiagnostics`, which **depends on** `CapsuleDomain`
  (`CapsuleDiagnostics → CapsuleDomain`), so **Domain/UI cannot import it** (would be a cycle).
  It also masks values after `--password/-p/--token/--secret/--registry-*` — and **its `-p`
  rule collides with `container run -p` publish-ports**. So the preview uses a **new
  Domain-local `CommandRedactor`** (operation-aware, never touches `-p`), not `SecretRedactor`;
  `SecretRedactor` stays in Diagnostics for the diagnostic bundle.
- Secrets are kept **off argv by design**: `registryLogin` takes no password; it is streamed
  via stdin. So argv is already secret-free for login; redaction in preview is belt-and-
  suspenders for `-e KEY=secret` env and `--build-arg`.

### Existing `commandPreview` + sheet conventions

- `commandPreview` accessors exist on `RunModel`, `MachineActionsModel` (create + set),
  `VolumeActionsModel`, `NetworkActionsModel`, `KernelManagerModel` — all
  `"container " + config.arguments.joined(" ")`. **Missing** on Build, Copy, Pull, Push, Load,
  Tag, Login, prune.
- The preview **render block is copy-pasted** across ~5 sheets (`QuickRunSheet`,
  `CreateMachineSheet`, `CreateNetworkSheet`, `ExecSheet`, `MachineSettingsSheet`).
- **Tiered complexity** = hand-rolled `DisclosureGroup` per sheet (`CreateMachineSheet`,
  `CreateNetworkSheet`, `CreateVolumeSheet`, `CopySheet`, `PropertiesEditorSheet`). No shared
  wrapper.
- `ExecSheet` builds its argv **inline** (`["container","exec","-it",id] + tokens`) bypassing
  the typed builder — the one op to consolidate onto `CLICommand`.

### Task model, terminal, navigation, persistence

- `OperationKind` enum (`pull/push/save/load/build/run/export/systemStart/copy/machineCreate/
  systemKernelInstall`); `OperationTask` (`@Observable`, holds title/kind/state/transcript) is
  driven by `TaskCenter.runStreaming/runAsync`. **`OperationTask` does NOT retain its argv** —
  the command lives only inside the captured closure.
- `TerminalRequest { containerID?, title, argv:[String] (incl. argv[0]), kind }` is the
  canonical "run argv in a terminal" value. Two escalation paths already exist: **embedded**
  (`ShellState.openTerminal`) and **external Terminal.app** (`openInExternalTerminal` →
  `openCommandInTerminalApp`, with a privileged `sudo` variant for DNS). `CommandTokenizer`
  tokenizes a typed command string.
- `CapsuleCommands` (the **main menu**, not a `MenuBarExtra`) already has a `⌘K Command
  Palette…` item **disabled, reserved for M11**. It receives `ShellState` (navigation +
  inspector + activity + terminal + logs reveal) but **not** the per-resource browser/action
  models, so item selection ("Run *selected* image") is not reachable from the menu today.
- Navigation = `ShellState.selection: SidebarSection` (`containers/images/volumes/networks/
  machines/system`); Settings is a separate `Settings { PreferencesView }` scene (⌘,). The
  System surface has **no sub-tab selector in `ShellState`**, so "Open system logs" and
  "Reclaim disk space" can only reach `.system` generically today.
- Persistence precedent = the **`ScopeStore` triad**: `ScopeStore` protocol +
  `InMemoryScopeStore` double (`CapsuleDomain`) + `UserDefaultsScopeStore` concrete
  (`CapsuleApp`, JSON→`UserDefaults` under one `capsule.*` key), injected in
  `AppEnvironment.live()`. `RunDraft`/`BuildDraft` live in `CapsuleDomain`, are
  `Sendable, Equatable` but **not `Codable`**. Registries (M6) and DNS (M8) are CLI-backed live
  state, **not** persistence precedents.
- The app is **not sandboxed** (verified 2026-07-01: `App/project.yml` sets
  `ENABLE_APP_SANDBOX: NO` and `App/Capsule.entitlements` states "Capsule runs UNSANDBOXED" —
  it spawns `Process` / the `container` CLI), so `BuildDraft.contextDirectory: URL?` persists
  as a plain path — no security-scoped bookmark.

### Resolved scope decisions (confirmed with user)

1. **Raw preview = single source of truth via relocation.** Move `CLICommand` + `ArgumentBuilder`
   from `CapsuleCLIBackend` down into `CapsuleBackend`. They are pure string/value logic (no
   `Process`) and belong next to the `Configuration` types they wrap. The CLI adapter keeps
   using them to execute; Domain/UI import the same factory for preview. (Rejected: a port
   `commandLine(for:)` method + a ~30-case operation enum — port bloat/duplication; and a
   hand-written approximation — violates acceptance.)
2. **Passthrough = universal escape hatch + plugin discovery.** A universal "run any
   `container …` command in terminal" entry, **plus** enumerate installed plugins from the two
   libexec dirs (gated on the service running) and surface each as a terminal-routed entry.
   (Rejected: also routing partially-implemented built-ins like `builder` — discovery-only;
   and generic-passthrough-only — misses the plugin acceptance line.)
3. **"Open raw command preview" + universal passthrough = one Command Console panel.** The
   standalone palette action and the universal passthrough are the same surface: shows the
   current best-fit invocation (from selection/active sheet), editable argv, copy, and escalate
   to embedded/external terminal.
4. **Presets open the sheet pre-filled**, ready to run, rather than firing instantly — keeps
   the user in control (matches the app's confirm-before-irreversible posture).
5. **Presets are Run/Build only** (per the goal). No preset surface for other ops.

## Architecture

Mirror the established strict-layer path (UI → Domain → Backend port → CLI adapter →
MockBackend), enforced by `ArchitectureGuardTests` (UI imports no Backend *adapter*; Domain
uses no `Process`). Reuse `TerminalRequest` + both escalation paths, `ShellState`, the
`ScopeStore` triad shape, `TaskCenter`, `CommandTokenizer`, and the normalized error model.

### Phase 1 — Relocate the argv factory + `CommandInvocation`

**Move** (no behavior change): `Sources/CapsuleCLIBackend/CLICommand.swift` and
`Sources/CapsuleCLIBackend/ArgumentBuilder.swift` → `Sources/CapsuleBackend/`. Update imports
in `CLIContainerBackend` and any callers. `CapsuleBackend` gains no `Process` dependency, so
the arch guard stays valid; **add** an arch-guard assertion that the moved files are
`Process`-free and that `CapsuleCLIBackend` still owns the runner.

**New value type** (`Sources/CapsuleDomain/CommandInvocation.swift` — **Domain, not Backend**,
because UI imports only `CapsuleDomain`; Domain imports `CapsuleBackend`, so it can build the
invocation from `config.arguments` and the now-relocated `CLICommand.*`):
```swift
public struct CommandInvocation: Sendable, Equatable {
    public let executable: String        // "container" — display only; runner owns the URL
    public let arguments: [String]        // faithful argv after the executable
    public init(_ arguments: [String], executable: String = "container")
    public var argv: [String] { [executable] + arguments }        // raw — for TerminalRequest
    public var displayString: String { ... }                       // redacted, space-joined
}
```
`arguments`/`argv` are the **raw** real argv (execution + terminal); `displayString` is the
**redacted** form used for all on-screen display and the copy button.

**Operation-aware redaction** — a new Domain-local `CommandRedactor`
(`Sources/CapsuleDomain/CommandRedactor.swift`): mask the value after
`--password/--passphrase/--token/--secret`, and the value portion of `-e`/`--env`/`--build-arg`
entries whose **key** matches `(?i)(pass|secret|token|key|cred)`; **never** redact
`-p`/`--publish`. It does **not** reuse `SecretRedactor` (different module — unreachable from
Domain — and a different, `-p`-safe policy).

### Phase 2 — A `CommandInvocation` per operation + reusable UI

**Uniform accessor.** Every op exposes its invocation:
- Config-backed: `CommandInvocation(arguments: config.arguments)`.
- `CLICommand`-only: `CommandInvocation(arguments: CLICommand.pullImage(reference:…))` etc.

Migrate the 5 existing `commandPreview: String` accessors to derive from `CommandInvocation`
(keep a `commandPreview` computed string where call sites still want a `String`). Add
`commandInvocation` accessors to the models that lack one: Build, Copy, Pull/Push/Load/Tag,
Login (redacted), prune. Consolidate `ExecSheet`'s inline argv onto a `CLICommand.execShell`
factory.

**Reusable views** (`CapsuleUI`):
- `CommandPreviewView(invocation: CommandInvocation, onEscalate: ((CommandInvocation) -> Void)?)`
  — monospaced, `.textSelection(.enabled)`, copy-to-clipboard button, optional "Open in
  Terminal" affordance. Replaces the ~5 copy-pasted blocks; **added to every sheet** (including
  the ones without a preview today).
- `AdvancedDisclosure { … }` — one wrapper for "common controls visible / advanced behind
  disclosure", adopted across Run/Build/Create*/Copy. Establishes the consistent stacking order
  on every sheet: **common control → advanced disclosure → raw preview → terminal fallback**.

**Post-run "just ran".** Add `invocation: CommandInvocation?` to `OperationTask`, threaded
through `TaskCenter.runStreaming/runAsync` (callers pass the invocation they already build).
`TaskTranscriptView`/Activity pane renders the exact command that ran, copyable, with a
"Re-open in terminal" escalation. Satisfies the "(or just ran)" clause.

### Phase 3 — Saved Run/Build presets

- Add `Codable` to `RunDraft`/`BuildDraft` (all-primitive except `BuildDraft.contextDirectory:
  URL?` → plain path; not sandboxed, so no bookmark). New persisted types in `CapsuleDomain`:
  `SavedRunPreset` / `SavedBuildPreset` (`Codable, Identifiable { id, name, draft }`) — named
  distinctly to avoid the existing **ephemeral** `BuildPreset` flag enum.
- **`PresetStore` triad** mirroring `ScopeStore`: `protocol PresetStore` + `InMemoryPresetStore`
  double (`CapsuleDomain`); `UserDefaultsPresetStore` concrete (`CapsuleApp`, keys
  `capsule.runPresets` / `capsule.buildPresets`), injected in `AppEnvironment.live()`.
- A `PresetsModel` (or methods on `RunModel`/`BuildModel`): `load`, `save(name:)`, `delete`,
  `apply(_:)` (loads the draft into the sheet). Build/Run models take a `presetStore` init param
  defaulting to `InMemoryPresetStore()` (mirrors `ContainerBrowserModel.scopeStore`).
- **UX** mirrors "Save Scope": a "Save as preset…" name prompt in the Run/Build sheets; edit =
  open the sheet pre-filled and re-save; a delete affordance in a sheet/menu list. Presets
  surface as dynamic entries in the palette + a **Presets** menu; selecting one opens its sheet
  pre-filled and ready to run.

### Phase 4 — Terminal passthrough + plugin discovery

- **Command Console** (`CapsuleUI`, a small panel/sheet/window): shows the current best-fit
  `CommandInvocation` (from selection / active sheet, else empty), an **editable argv** field
  (tokenized via `CommandTokenizer`), copy, and **escalate** to embedded
  (`ShellState.openTerminal`) or external (`openInExternalTerminal`) terminal. This single
  surface backs both the standalone "Open raw command preview" palette action and the universal
  passthrough. Any sheet/action can hand its invocation to the same escalation path (a
  `TerminalRequest(argv: invocation.argv, kind: .runInteractive)`).
- **Plugin discovery**: `protocol PluginDiscovering { func installedPlugins() -> [PluginInfo] }`
  in `CapsuleDomain`; concrete `LibexecPluginScanner` in `CapsuleApp` (lists `container-*`
  binaries under the two libexec dirs). `PluginInfo { name, path }`. A `PluginCatalogModel`
  (`@Observable`, Domain) exposes the list, **gated on `systemModel.health.isRunning`**, each
  surfaced as a palette/menu entry that opens `container <plugin>` in the terminal. (Filesystem
  scan is not `Process`, but the seam keeps Domain decoupled and testable with a fake lister.)

### Phase 5 — Command catalog → palette + menus

- **`CommandCatalog`** (`CapsuleUI` — it references `ShellState`/sheet presentation, which are
  UI; `CapsuleApp` imports `CapsuleUI` so the menu can render it too): a single
  `CommandCatalog.actions(_ ctx: CommandContext) -> [CommandAction]` where `CommandAction {
  id, title, subtitle, symbol, shortcut: CommandShortcut?, isEnabled: Bool, run: () -> Void }`
  and `CommandContext` bundles the live app state/closures actions need (shell, system model,
  browser/action models, selection, sheet-presentation + window closures). **Both** the ⌘K
  palette and the menu bar render from this one function so they cannot drift. Dynamic entries
  (presets, plugins) are appended. The pure fuzzy-filter ranking is a separate Domain helper
  (`FuzzyMatch`) so it is unit-testable without UI.
- **Palette UI** (`CapsuleUI`, `CommandPaletteView`): a ⌘K overlay (sheet) with a search field
  + fuzzy-filtered list; Enter runs the focused action; ↑/↓ navigate; Esc dismisses. Actions
  needing an absent selection render disabled with a hint subtitle; navigation actions stay
  enabled.
- **Wiring**: thread the existing `@State` models from `CapsuleScene` into `CapsuleCommands`
  and the palette (direct threading — no `FocusedValue` precedent exists). **Enable** the
  reserved ⌘K item to present the palette. Add a menu item per catalog action, grouped into the
  existing menus (View/Resource/Machine) + a new **Commands** and **Presets** menu. Assign
  shortcuts avoiding the live set (⌥⌘I, ⌘J, ⇧⌘L, ⌘R, ⌘K, ⌘,).
- **System deep-link**: add `systemTab: SystemTab` to `ShellState`; `SystemDetailView` reads it
  so "Open system logs" → `.serviceLogs` and "Reclaim disk space" → `.storage` land on the
  right sub-pane (today both only reach `.system`).

## The 12 palette/menu actions → existing entry points

| Action | Entry point | Notes |
|---|---|---|
| Run selected image | `RunModel` + `QuickRunSheet`; `imageBrowserModel.selectedImages.first` | disabled w/ hint if no image selected |
| Exec shell in selected container | `ContainerLifecycleModel.openShell(id:)`; `containerBrowserModel.selection` | disabled w/ hint if none |
| Follow logs | `LogsModel` + `openWindow(id: LogWindow.id)` | selected container if any |
| Build from current folder | `BuildModel` + `BuildSheet` | opens folder picker if unset |
| Pull image | `ImageActionsModel.pull` + `PullImageSheet` | |
| Copy file to container | `CopyModel` + `CopySheet` | |
| Export container | `ContainerLifecycleModel.export(id:to:)` | selected container |
| Start / Stop services | `actions.recover(.startServices)` / `actions.stopServices()` | already in Resource menu |
| Open system logs | `shell.selection = .system` + `shell.systemTab = .serviceLogs` | always enabled |
| Reclaim disk space | `shell.selection = .system` + `shell.systemTab = .storage` (+ `StorageDashboardModel.reclaim`) | always enabled |
| Toggle inspector | `shell.toggleInspector()` | already a command |
| Open raw command preview | Command Console panel | always enabled |

## Headline behaviors (the power-user moments)

- **One palette, every action, no drift.** ⌘K fuzzy-searches one catalog that the menu bar
  also renders, so the keyboard surface and the menu surface are provably the same set.
- **The GUI is honest.** Every sheet and every finished task shows the exact, copyable argv the
  real builder produced — not an approximation — so anything done in the GUI is reproducible in
  a shell, and secrets never appear.
- **Presets make repetition cheap.** A configured Run/Build becomes a named, editable preset
  re-invokable from palette or menu, pre-filled and ready.
- **Nothing is a dead end.** Any command escalates to the integrated or external terminal, and
  installed plugins (when the service runs) get a terminal route even though Capsule has no UI
  for them — the GUI never blocks an expert from the full CLI.

## Cross-cutting

- **Gating.** Selection-dependent palette/menu actions disable with a hint when nothing is
  selected; plugin entries appear only when `health.isRunning`; the menu items mirror the same
  enablement as their catalog actions.
- **Secrets.** Preview/console display always passes through the operation-aware redactor; the
  real argv handed to the runner/terminal is unredacted. Login stays stdin-only.
- **Errors.** Escalation and passthrough reuse the existing terminal paths; preview generation
  is pure and cannot fail. Preset decode failures fall back to an empty list (mirrors
  `UserDefaultsScopeStore`).
- **Composition root.** Construct `PresetStore`(s), `PluginCatalogModel`, `CommandCatalog`, and
  the Command Console plumbing in `AppEnvironment.live()`; thread the existing browser/action
  models + new stores into `CapsuleCommands` and the palette via `CapsuleScene`.

## Testing

- **Unit (XCTest).** `CommandInvocation` construction + `argv`/`displayString`; operation-aware
  redaction (`-p`/`--publish` **preserved**, `-e SECRET=…`/`--build-arg TOKEN=…` masked,
  `--password` value masked, login argv already secret-free); `CommandCatalog` enable/disable
  per `Context` (selection present vs absent); fuzzy filter ranking; `PresetStore` round-trip +
  `RunDraft`/`BuildDraft` `Codable` (incl. `contextDirectory` path round-trip); plugin scan
  with an injected fake FS lister (two libexec dirs, `container-*` filter, non-executables
  ignored); `PluginCatalogModel` gating on running state; `ShellState.systemTab` deep-link.
- **Architecture guard.** Moved `CLICommand`/`ArgumentBuilder` are `Process`-free and now in
  `CapsuleBackend`; `CapsuleCLIBackend` still owns `CLIProcessRunner`; UI imports no Backend
  adapter; Domain no `Process`.
- **Integration (`CAPSULE_INTEGRATION=1`).** The relocated `CLICommand` still produces argv the
  real CLI accepts (extend the existing argv-validation tests); `LibexecPluginScanner` against
  the real libexec paths (asserts it returns cleanly whether or not plugins are installed —
  mirrors the M10 "guard skips cleanly" pattern).
- **GUI smoke (live).** ⌘K opens the palette and runs an action; a sheet's preview copies the
  exact command; save a Run preset and re-run it from the palette/menu; escalate a command to
  the terminal via the Command Console; a plugin entry appears when the service is running (or
  the console passthrough runs an arbitrary `container` command otherwise).

## Plan phasing (for the implementation plan)

1. **Relocate** `CLICommand` + `ArgumentBuilder` → `CapsuleBackend`; add `CommandInvocation`
   + operation-aware redactor; update arch guard. (No behavior change; all existing tests green.)
2. **Per-op `CommandInvocation`** accessors + migrate the 5 `commandPreview`s + consolidate
   `ExecSheet` argv; reusable `CommandPreviewView` + `AdvancedDisclosure`; adopt on **all**
   sheets; add `OperationTask.invocation` + thread through `TaskCenter`; render in
   `TaskTranscriptView`.
3. **Presets**: `Codable` drafts + `SavedRunPreset`/`SavedBuildPreset` + `PresetStore` triad +
   `UserDefaultsPresetStore` + save/edit/delete/apply UX in Run/Build sheets.
4. **Passthrough + plugins**: Command Console panel + invocation escalation everywhere;
   `PluginDiscovering` seam + `LibexecPluginScanner` + `PluginCatalogModel`.
5. **Catalog + palette + menus**: `CommandCatalog` + `CommandPaletteView` (⌘K) + enable the
   reserved item; menu entries per action (Commands/Presets menus); selection threading;
   `ShellState.systemTab` + `SystemDetailView` deep-link.
6. **Tests + review + GUI smoke**: unit/arch/integration; whole-branch 3-lens adversarial
   review; live interactive GUI smoke of the headline flows.

## Non-goals (YAGNI)

- No `MenuBarExtra`/status-item surface (Capsule uses the main menu).
- No preset surface beyond Run/Build; no preset import/export/sharing.
- No dedicated terminal routes for partially-implemented built-ins (e.g. `builder`) — reachable
  via the generic passthrough only.
- No `FocusedValue` bridge (direct model threading matches the codebase).
- No dynamic parsing of `container --help` for built-in-subcommand diffing (plugin **directory**
  discovery only).
- No security-scoped bookmarks (app is not sandboxed).
- No new resource surfaces or new lifecycle operations.
