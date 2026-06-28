# Milestone 4 · App Shell, Onboarding & System Status — Design

Date: 2026-06-28
Status: Approved (autonomous via `/goal`)

## Goal

Build the navigational frame and the system-health story so Capsule is usable
before any resource feature lands: a `NavigationSplitView` shell with a resource
sidebar, content column, trailing `.inspector`, and a bottom Activity pane;
first-launch onboarding; a global system-health banner wired to the `container`
system commands; explicit Start/Stop Services; a menu bar; and dark-mode /
increased-contrast-correct colors. Crucially, "no data" must never be rendered as
"healthy": when the daemon is down, resource lists show a health/error state with
recovery actions, not an empty state.

## Architecture & layering

The strict layering is preserved (guarded by `ArchitectureGuardTests`):

```
CapsuleApp (composition root)  ──▶ UI, Domain, CLIBackend, Diagnostics, Backend
CapsuleUI                      ──▶ Domain           (NEVER Backend/Diagnostics)
CapsuleDomain                  ──▶ Backend (port)   (NEVER UI, NEVER Process, NEVER Diagnostics)
CapsuleDiagnostics             ──▶ Domain
CapsuleCLIBackend              ──▶ Backend, Diagnostics
```

Consequence: the UI binds to **domain-native** value types only. The health model
lives in Domain and exposes `SystemVersion` / `SystemFeature` mirrors — never
`BackendVersion` / `BackendCapabilities`. Because Domain cannot import Diagnostics,
error normalization (`Error → CapsuleError`) is **injected as a closure** into the
domain model from the composition root, which passes `ErrorNormalizer.normalize`.

## Components (by layer)

### 1. CapsuleBackend (port + mock) — system lifecycle

- `ContainerBackend` gains: `systemStatus() -> SystemRunState`, `startSystem()`,
  `stopSystem()`.
- New value type `SystemRunState { case running, stopped }`.
- `MockBackend`: backing `systemRunState` field, mutated by start/stop, with the
  existing `failure` injection honored so tests can simulate a down daemon.

### 2. CapsuleCLIBackend (adapter)

- `CLICommand.systemStatus()` = `["system", "status"]`,
  `.startSystem()` = `["system", "start"]`, `.stopSystem()` = `["system", "stop"]`.
- `CLIContainerBackend` implements the three: status parsed leniently (exit 0 +
  stdout/stderr mentions "running" → `.running`; explicit "not running"/"stopped"
  → `.stopped`; a spawn/XPC/connection failure throws and is normalized upstream).
  start/stop run-checked.

### 3. CapsuleDiagnostics — error normalization

Extend `ErrorNormalizer.normalize` to map `BackendError`:
- `.executableNotFound(path)` → `.daemonUnavailable` (CLI missing) with recovery
  `[.openLogs, .exportDiagnostics]`.
- `.nonZeroExit(command, code, stderr)`: if `stderr` matches a **daemon-down /
  XPC-startup** signature (`connection refused`, `xpc`, `not running`, `could not
  connect`, `failed to connect`, `launchd`, `no such file or directory` on the
  socket) → `.daemonUnavailable` with `[.startServices, .openLogs,
  .exportDiagnostics]`; otherwise `.commandFailed`.
- `.decodingFailed(msg)` → `.unknown`.
- A small, table-tested `daemonSignature(in:)` helper holds the substrings.

### 4. CapsuleDomain — health state machine

- `SystemVersion { client: String; server: String? }` (UI-facing mirror).
- `SystemFeature` enum mirroring `BackendFeature` (system, containers, images,
  volumes, networks, registries, machines, builder, logsFollow) so the UI can gate
  sidebar items without importing Backend.
- `SystemHealth` enum: `.unknown`, `.checking`,
  `.running(version: SystemVersion, features: Set<SystemFeature>)`, `.stopped`,
  `.unavailable(ErrorDetail)`. Computed: `isHealthy`, `isRunning`,
  `bannerKind` (healthy/warning/unhealthy/info).
- `CompatibilityWarning` derivation: client below `minimumSupportedClient`, or a
  client/server major mismatch → an optional human string surfaced in the banner.
- `SystemStatusModel` (`@MainActor @Observable`): owns `health`, drives
  `refreshStatus()` (status → version → derive features/compat), `startServices()`,
  `stopServices()`. Holds the backend, an injected `normalize: (Error) ->
  CapsuleError` (default: passthrough + `.unknown`), and an injected
  `onActivity: (ActivityEvent) -> Void` hook for the Activity pane / logging.
  Maps `BackendCapabilities` → `Set<SystemFeature>` internally.

`WorkspaceModel` is unchanged except that resource loading is now **health-aware**:
its `loadState` is only meaningful when the system is running; the UI consults
`SystemStatusModel.health` first.

### 5. CapsuleUI — the shell

- `AppShellView(systemModel:workspaceModel:shell:)` — `NavigationSplitView`
  (sidebar | content), a top `SystemHealthBanner`, a trailing `.inspector` with
  `.inspectorColumnWidth(min: 240, ideal: 320, max: 420)` and a toolbar toggle, and
  a persistent bottom `ActivityPaneView` (collapsible) with a reserved terminal
  slot. Selection + pane visibility live in an observable `ShellState`.
- `SidebarSection` enum: Containers, Images, Volumes, Networks, Machines, System.
  Items disabled/greyed when the matching `SystemFeature` is unavailable; a health
  dot reflects overall status.
- `SystemHealthBanner` — renders `SystemHealth`: unhealthy (error tint) with the
  `ErrorDetail` explanation + recovery buttons (Start Services first); running
  (success tint) with version info; compatibility warning (caution tint).
- `ContentColumnView` — **health-gated**: if not running, shows a
  `ContentUnavailableView` health/error state with recovery actions (NOT an empty
  list); if running, shows the resource placeholder/list.
- `InspectorView`, `ActivityPaneView` (Logs/Tasks/Progress placeholder tabs +
  terminal slot), `SystemDetailView` (version, Start/Stop, Export Diagnostics).
- `OnboardingView` — first-launch sheet gated by
  `@AppStorage("capsule.hasCompletedOnboarding")`; welcome → CLI check → Start
  Services → done.
- `RecoveryAction` handling: the shell maps `.startServices` →
  `systemModel.startServices()`, `.retry` → `refreshStatus()`, `.openLogs` → reveal
  the Activity pane Logs tab, `.exportDiagnostics`/others → injected callback;
  unhandled cases log and no-op.
- `CapsuleColors` — semantic colors (success / caution / error / surfaces) defined
  for light + dark, with `@Environment(\.colorSchemeContrast)` increasing tint
  saturation / borders when `.increased`.

### 6. CapsuleApp — composition & menus

- `AppEnvironment` builds `SystemStatusModel` (injecting `ErrorNormalizer.normalize`
  and an activity sink) alongside `WorkspaceModel`; both flow into `CapsuleScene`.
- `CapsuleScene` renders `AppShellView`, presents `OnboardingView` on first launch,
  and triggers `refreshStatus()` on appear.
- Menu bar via `CapsuleCommands`: App (Updates), File, Edit, **View** (Toggle
  Inspector, Toggle Activity Pane, Toggle Sidebar), **Resource** (`CommandMenu`:
  Refresh, Start Services, Stop Services; a disabled "Command Palette…" hook for
  Milestone 11), Window, Help. Commands operate on the shared models / `ShellState`.

## Error handling

All backend failures become `CapsuleError` via the injected normalizer; the banner
and content column render `ErrorDetail`. A down/XPC-failing daemon resolves to
`.daemonUnavailable` → unhealthy banner + Start Services + Open Logs, and resource
columns show the same error state rather than an empty list. Compatibility
mismatches surface as a non-blocking caution banner.

## Testing (TDD)

Unit-tested (red→green per slice):
- `CLICommand` system status/start/stop argv.
- `CLIContainerBackend` system status/start/stop via `StubProcessRunner` (incl.
  lenient status parsing + non-zero → throw).
- `MockBackend` system run-state mutation + failure injection.
- `ErrorNormalizer` `BackendError` mapping incl. `daemonSignature` table.
- `SystemHealth` derivation, `CompatibilityWarning`, and `SystemStatusModel` state
  machine (running / stopped / unavailable / start / stop) against `MockBackend`.
- `SidebarSection` ↔ `SystemFeature` availability mapping (pure function).
- Pure view-helper functions (banner kind, status text) where extracted.

View rendering is validated behaviorally via `make app` + launch (acceptance);
SwiftUI views are kept thin with logic pushed into tested helpers/models.

## Acceptance

`make ci` green (build zero-warning, swift-format --strict, arch guard, headers, all
unit tests) and `make app` builds. Behaviorally: launches into the split-view shell;
services stopped → clear unhealthy banner + working Start Services; running → version
info + healthy status; inspector toggles/resizes; bottom Activity pane present;
light/dark/increased-contrast all render correctly.

## Out of scope (later milestones)

Real resource lists/inspectors (M5+), detachable terminal windows (slot only),
command palette (M11, hook only), Sparkle updater wiring, real diagnostics export UI
beyond invoking the existing builder.
