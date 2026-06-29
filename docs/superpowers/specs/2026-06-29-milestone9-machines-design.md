# Milestone 9 · Machines surface — Design

**Date:** 2026-06-29
**Branch:** `milestone-9-machines`
**Phase:** 3 (Systems surface), following M8 (Volumes/Networks/DNS).

## Goal

Add the persistent-Linux-environment workflows where a GUI clearly beats the CLI by
making delayed-effect config obvious. Build a **Machines** browser from `machine list`
with a default-machine badge, plus create / run-shell / inspect / set / set-default /
logs / stop / delete. The headline win is surfacing **delayed-effect configuration**
(`machine set` only applies after restart) and **implicit boots** (`machine run` boots a
stopped machine) — things the CLI leaves invisible.

## Ground truth: the real `container machine` CLI (v1.0.0, probed 2026-06-29)

| Subcommand | Shape | Notes |
|---|---|---|
| `machine list [--format json\|table] [-q]` | JSON array | columns: NAME, CREATED, IP, CPUS, MEMORY, DISK, STATE, DEFAULT. Empty = `[]`. |
| `machine inspect [<id>]` | JSON (no `--format`) | uses default if id omitted; errors when no id and no default. |
| `machine create [opts] <image>` | streams progress | `-n/--name`, `--set-default`, `--no-boot`, `--cpus`, `--memory`, `--home-mount <ro\|rw\|none>`, `-a/--arch` (def arm64), `--os` (def linux), `--platform`, registry/progress opts. **No `--nested-virtualization`, no `--kernel`.** |
| `machine set [-n <name>] [<setting>...]` | — | settings: `cpus=<n>`, `memory=<size>`, `home-mount=<ro\|rw\|none>` ONLY. **Takes effect after restart.** |
| `machine set-default <id>` | — | id required. No "unset"; revert = set-default back to prior default. |
| `machine logs [--boot] [-f] [-n <lines>] [<id>]` | text | `--boot` = boot log; default = stdio/session log. |
| `machine run [opts] [<exe>] [<args>...]` | interactive/stream | `-n`, `-i`, `-t`, `-d`, env/user/workdir/etc. **Boots the machine if necessary.** default exe = login shell. |
| `machine stop [<id>]` | — | uses default if omitted. |
| `machine delete <id>` (alias `rm`) | — | id required. **Removes persistent storage.** |

### Resolved scope decisions (confirmed with user)
1. **nested-virt & kernel** — omitted from the create wizard and settings form (CLI cannot
   drive them); surfaced **read-only in the inspector only if** they appear in inspect JSON.
2. **Command palette** — the app's palette is a disabled stub owned by M11. Ship "Open
   Machine Shell" as toolbar + main-menu + row context-menu actions now; defer palette
   wiring to M11.
3. **Live wire-shape validation** — during implementation, create one real (alpine)
   machine to capture exact `list`/`inspect` JSON and run a gated live integration test,
   then delete it. Avoids M8-style fixture guessing (the DNS-shape bug).

## Architecture

Mirror the **Networks vertical slice** (M8) across the strict layers
(UI → Domain → Backend port → CLI adapter → MockBackend). Reuse existing infrastructure:
embedded terminal (`TerminalRequest` / `ShellState.openTerminal`), `LogsModel` +
`LogsPaneView`, `TaskCenter` streaming/async tasks, terminal/clipboard fallback callbacks,
and the normalized error model (`CapsuleError` + `normalize`).

**Already present (no new plumbing needed):** `BackendFeature.machines` /
`SystemFeature.machines` capability flags (gated to system-running + client ≥ 1.0.0),
`SidebarSection.machines` (renders + disables automatically), `listMachines()` across
port/CLI/Mock, `CLIMachineRecord`, `OutputParser.parseMachines`, and an existing
`ContainerLifecycleModel.openMachineShell(name:)` helper. Today `ContentColumnView` routes
`.machines` to the placeholder; this milestone fills it in.

### Layer changes

**Backend port (`CapsuleBackend`):**
- Expand `MachineSummary` `{name, state}` → `{name, state, createdAt, ipAddress, cpus,
  memory, disk, isDefault}` plus optional inspected-detail fields (`kernel`,
  `nestedVirtualization`, `homeMount`) decoded only when present.
- Add: `inspectMachine(id: String?) -> Parsed<MachineSummary>` (no `--format`; default when
  nil), `createMachine(_ config: MachineConfiguration) -> AsyncThrowingStream<OutputLine,
  Error>` (image pull + boot has progress, like `pullImage`/`buildImage`),
  `setMachine(name: String?, settings: MachineSettings)`, `setDefaultMachine(id:)`,
  `stopMachine(id: String?)`, `deleteMachine(id:)`, `fetchMachineLogs(id:tail:boot:)`,
  `followMachineLogs(id:boot:)`.
- Interactive shell does **not** go through the port — it is a `TerminalRequest` terminal
  session (exactly like container `exec -it`).

**CLI adapter (`CapsuleCLIBackend`):**
- `CLICommand` builders for each subcommand (via `ArgumentBuilder`). `inspect` uses no
  `--format`. `MachineConfiguration.arguments` / `MachineSettings.arguments` are the single
  source of truth for create/set argv.
- Expand `CLIMachineRecord` to the real JSON shape (validated live), keep lossy decoding.
- `createMachine` streams via the raw-stream path (progress lines).

**MockBackend:** mutable `machines` state + call-inspection fields
(`lastCreatedMachine`, `lastMachineSettings`, `lastSetDefaultID`, `lastStoppedMachine`,
`lastDeletedMachine`, `did...`), sample machines (incl. one default), and implementations
of every new method (create appends + optionally sets default; set records settings; stop
flips state to stopped; delete removes; inspect filters).

**Domain (`CapsuleDomain`) — new types, mirroring Networks:**
- `Machine` (domain struct) + `MachineState` enum (running / stopped / unknown, parsed from
  the state string — drives badges AND implicit-boot detection).
- `MachineBrowserModel` (`@MainActor @Observable`): `allMachines`, `loadState`, `selection`,
  `searchText`, `rows`, `refresh()`, `inspect(id:)` — copy of `NetworkBrowserModel` shape.
- `MachineActionsModel` (`@MainActor @Observable`): `busy`/`notice`/`confirmation`, plus
  create/set/setDefault/revertDefault/stop/delete, validation + `commandPreview`,
  **restart-required tracking**, and **implicit-boot detection**.
- `MachineDraft` (create wizard) + `MachineSettingsDraft` (set form);
  `MachineConfiguration` + `MachineSettings` (backend value types / argv builders);
  `MachineValidation` (cpus = positive int; memory matches `^\d+[MG]$`; image required;
  home-mount ∈ {rw,ro,none}); `ConfirmationRequest.deleteMachine(name:)`.
- `MachineImagePreset` — curated distro presets (alpine:3.22, ubuntu:24.04, debian:12,
  fedora:40) + a custom-image escape hatch.

**UI (`CapsuleUI`):**
- `MachineListView` — `Table` (Name, State badge, Default star, CPUs, Memory, IP, Created),
  search, multi-select, context menu, toolbar (Create / Refresh + per-selection actions).
  Mirrors `NetworkListView` load-state handling.
- `MachineInspectorView` — Summary tab (friendly fields incl. read-only kernel/nested-virt
  when present) + Raw JSON tab. Mirrors `NetworkInspectorView`.
- `CreateMachineSheet` — the wizard (sections: Image/distro preset + custom; Resources
  cpus/memory/home-mount; Options name/set-default/no-boot + advanced arch/os/platform),
  with first-boot-provisioning and persistent-home explanatory copy and a command preview.
  Create runs as a streaming `TaskCenter` task; the sheet closes and progress shows in
  Activity.
- `MachineSettingsSheet` — set form (cpus/memory/home-mount) with command preview.
- `MachineLogsView` — Boot vs Session **sub-tabs**, reusing `LogsPaneView`.
- Banners/sheets: restart-required banner, implicit-boot notice, set-default success+Undo,
  stop success (Open Shell / Restart), delete `ConfirmationSheet`.

## Headline behaviors (the GUI-beats-CLI moments)

- **`set` → "Restart required" banner.** After a successful `set`, the machine is marked
  pending-restart (`MachineActionsModel.pendingRestart: Set<String>`); a prominent banner
  persists on its detail/inspector until restart, with a **Restart Now** action (stop →
  boot). Cleared on stop/restart. This is the centerpiece of the milestone.
- **Implicit boot.** Before opening a shell / running, read the machine's current
  `MachineState`. If not running, show an implicit-boot notice ("Capsule is booting 'X' to
  open the shell"); after, refresh to confirm running. Detection is state-before-action.
- **set-default + revert.** "Make Default" → `setDefaultMachine(id)`; record the prior
  default first. Success notice: "'X' is now the default. [Undo]" where Undo re-sets the
  prior default. List/inspector show a star badge on the default.
- **logs boot vs session.** Two sub-tabs backed by `LogsModel(boot: true/false)`. Reuse the
  existing model + `LogsPaneView` via a small **additive** `LogSource` seam: a new
  source-based init drives both container and machine logs; existing container call sites
  keep working through a back-compat convenience init, so the working surface is untouched.
- **stop → reopen/restart banner.** `stopMachine` success notice offers **Open Shell**
  (implicit boot) and **Restart** (boot again).
- **delete → explicit confirmation.** `ConfirmationSheet` warns that **persistent storage
  (home + disk) is removed irreversibly**; requires confirmation; success banner after.

## Cross-cutting

- **Gating.** Whole surface behind `health.supports(.machines)`. The Apple-silicon/runtime
  requirement is already encoded: `.machines` is a runtime feature requiring the system
  service up (server version present) and client ≥ 1.0.0. Fill the `.machines` case in
  `ContentColumnView` for the supported state; keep the existing unsupported message for the
  gated state.
- **Errors + terminal fallback.** Every action routes through `normalize` → `CapsuleError`
  → `notice`/`ConfirmationSheet`. The shell uses `TerminalRequest` + embedded terminal with
  terminal-app/clipboard fallback (reuse the `openMachineShell`/`launchOrCopy` pattern).
  No privileged/sudo path is needed (machines don't require admin).
- **Composition root.** Construct `MachineBrowserModel` + `MachineActionsModel` in
  `AppEnvironment.live()` (wiring `onActivity`, `launchTerminal`, `copyCommand`,
  `taskCenter`); thread through `CapsuleScene → RootView → AppShellView → ContentColumnView`
  `.machines` case → `MachineListView`. Add a **Machine** main-menu in `CapsuleCommands`
  (Open Shell / Create / Inspect / Make Default / Stop / Delete / View Logs) gated on
  selection + capability.

## Testing

- **Unit tests against `MockBackend`** (the stated acceptance bar): browser
  refresh/loadState/selection/rows; actions create/set/setDefault/revertDefault/stop/delete
  via call-inspection; validation (cpus/memory/name/image/home-mount); confirmation builder;
  restart-required tracking; implicit-boot detection; `commandPreview`;
  `MachineConfiguration`/`MachineSettings` argv; `OutputParser.parseMachines` with a
  real-shape fixture; `LogSource` seam (container logs unchanged).
- **One gated live integration probe** (`CAPSULE_INTEGRATION=1`): create alpine machine →
  list / inspect (capture exact JSON, lock fixtures) → set → set-default → logs → stop →
  delete. Creates and **deletes** a real machine.
- **Architecture guard** stays green (UI imports no Backend; Domain imports no UI / no
  `Process`). `make ci` green; `.app` builds/links/signs.

## Plan phasing (for the implementation plan)

1. Backend port + `MachineSummary` expansion + value types (`MachineConfiguration`,
   `MachineSettings`) + MockBackend + CLI adapter/wire/parser.
2. Domain models (`Machine`, `MachineState`, browser + actions models, drafts, validation,
   confirmation, restart tracking, implicit-boot, image presets).
3. List + inspector UI.
4. Create wizard.
5. Settings form (restart banner) + set-default/revert + stop banner + delete confirmation.
6. Shell terminal action + boot/session logs (LogSource seam) + Machine menu/toolbar.
7. Composition-root wiring + capability gating in `ContentColumnView`.
8. Live wire-shape probe + integration test + whole-branch adversarial review.

## Non-goals (YAGNI)

- No command-palette implementation (M11 owns it).
- No nested-virtualization / kernel configuration (CLI can't; inspector read-only only).
- No detached `machine run -d` task orchestration beyond the interactive shell + create
  task (one-shot `run <cmd>` as an Activity task is a possible later follow-up, not M9).
