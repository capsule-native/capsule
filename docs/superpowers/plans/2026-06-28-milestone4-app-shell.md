# Milestone 4 · App Shell, Onboarding & System Status — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans /
> subagent-driven-development to implement task-by-task. Steps use `- [ ]` syntax.

**Goal:** Build the `NavigationSplitView` shell, first-launch onboarding, and the
system-health story (status/version/start/stop) so Capsule is usable before any
resource feature lands — with daemon-down rendered as an explicit unhealthy state,
never as empty data.

**Architecture:** Bottom-up. Add system lifecycle to the backend port + CLI adapter +
mock; extend error normalization to detect daemon/XPC failures; build a domain health
state machine (`SystemStatusModel` / `SystemHealth`) that exposes UI-native types and
takes an injected normalizer; build the SwiftUI shell binding only to the domain; wire
composition + menus in `CapsuleApp`.

**Tech Stack:** Swift 6 / SwiftPM, SwiftUI (macOS 26), Observation, XCTest, XcodeGen.

## Global Constraints

- macOS 26.0+, Apple silicon, Swift tools 6.0 (`swiftLanguageModes: [.v5]`).
- Layering (guarded by `ArchitectureGuardTests` + `Scripts/check-architecture.sh`):
  UI imports **only** `CapsuleDomain` (never Backend/CLIBackend/Diagnostics); Domain
  imports **only** `CapsuleBackend` (never UI, never `Foundation.Process`, never
  Diagnostics).
- Every Swift file starts with the standard 5-line license header
  (`//  <name>\n//  Capsule\n//\n//  Copyright © 2026 Capsule. All rights reserved.\n//`).
- `make ci` must stay green: `swift build` zero warnings, `swift format lint --strict`,
  arch guard, headers, all unit tests. `make app` must build.
- Minimum supported client version: `SemanticVersion(1, 0, 0)` (already in Backend).

---

### Task 1: System lifecycle on the backend port + MockBackend

**Files:**
- Modify: `Sources/CapsuleBackend/ContainerBackend.swift`
- Create: `Sources/CapsuleBackend/SystemRunState.swift`
- Modify: `Sources/CapsuleBackend/MockBackend.swift`
- Test: `Tests/CapsuleUnitTests/MockBackendTests.swift`

**Interfaces — Produces:**
- `enum SystemRunState: String, Sendable, Equatable, Codable { case running, stopped }`
- `ContainerBackend.systemStatus() async throws -> SystemRunState`
- `ContainerBackend.startSystem() async throws`
- `ContainerBackend.stopSystem() async throws`
- `MockBackend(systemRunState:)` init param (default `.running`); start/stop mutate it;
  `failure` injection still throws.

- [ ] **Step 1:** Write failing tests: mock defaults to `.running`; `stopSystem()` →
  `systemStatus() == .stopped`; `startSystem()` → `.running`; with `failure` set,
  `systemStatus()` throws.
- [ ] **Step 2:** Run `swift test --filter MockBackendTests` → FAIL (no such members).
- [ ] **Step 3:** Add `SystemRunState`; add three protocol requirements; implement in
  `MockBackend` (backing `systemRunState` var guarded by the existing lock, honoring
  `failure`).
- [ ] **Step 4:** Run filter → PASS; `swift build` zero warnings.
- [ ] **Step 5:** `make format`; commit `feat(backend): add system status/start/stop to port + mock`.

---

### Task 2: CLICommand argv for system status/start/stop

**Files:**
- Modify: `Sources/CapsuleCLIBackend/CLICommand.swift`
- Test: `Tests/CapsuleUnitTests/CLICommandTests.swift`

**Interfaces — Produces:** `CLICommand.systemStatus() -> ["system","status"]`,
`CLICommand.startSystem() -> ["system","start"]`, `CLICommand.stopSystem() -> ["system","stop"]`.

- [ ] **Step 1:** Failing tests asserting the three argv arrays.
- [ ] **Step 2:** Run `swift test --filter CLICommandTests` → FAIL.
- [ ] **Step 3:** Add the three factories using `ArgumentBuilder("system", "…")`.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(cli): system status/start/stop argv`.

---

### Task 3: CLIContainerBackend system lifecycle (lenient status parse)

**Files:**
- Modify: `Sources/CapsuleCLIBackend/CLIContainerBackend.swift`
- Create: `Sources/CapsuleCLIBackend/SystemStatusParser.swift`
- Test: `Tests/CapsuleUnitTests/CLIContainerBackendTests.swift`,
  `Tests/CapsuleUnitTests/SystemStatusParserTests.swift`

**Interfaces — Produces:**
- `enum SystemStatusParser { static func parse(stdout:String, stderr:String) -> SystemRunState }`
  — `.running` if either stream (lowercased) contains "running" and not "not running";
  "not running"/"stopped"/"not started"/empty → `.stopped`.
- `CLIContainerBackend.systemStatus/startSystem/stopSystem`. status uses `runner.run`
  directly (does NOT throw on non-zero — a stopped service may exit non-zero) and feeds
  both streams to the parser; a spawn failure (executableNotFound) still propagates.
  start/stop use the existing `runChecked`.

- [ ] **Step 1:** `SystemStatusParserTests`: "apiserver is running" → running;
  "apiserver is not running" → stopped; "" → stopped; "Stopped" → stopped.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement `SystemStatusParser`.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** `CLIContainerBackendTests` (via `StubProcessRunner`): stub stdout
  "running" → `.running`; start/stop issue `system start`/`system stop` and a non-zero
  exit on start throws `BackendError.nonZeroExit`.
- [ ] **Step 6:** Run → FAIL; implement the three methods; Run → PASS; `swift build`.
- [ ] **Step 7:** `make format`; commit `feat(cli): system lifecycle on CLI backend`.

---

### Task 4: ErrorNormalizer maps BackendError + daemon/XPC detection

**Files:**
- Modify: `Sources/CapsuleDiagnostics/ErrorNormalization.swift`
- Test: `Tests/CapsuleUnitTests/ErrorNormalizerTests.swift`

**Interfaces — Produces:** `ErrorNormalizer.normalize` now maps `BackendError`:
- private `daemonSignature(in text:String) -> Bool` — true if lowercased text contains
  any of: `connection refused`, `xpc`, `could not connect`, `failed to connect`,
  `not running`, `launchd`, `apiserver`, `no such file or directory`.
- `.executableNotFound(path)` → `.daemonUnavailable(message:"The container CLI could not
  be found at \(path).", recovery:[.openLogs,.exportDiagnostics])`.
- `.nonZeroExit(command,code,stderr)` → `daemonSignature` true →
  `.daemonUnavailable(message: stderr-or-default, recovery:[.startServices,.openLogs,.exportDiagnostics])`;
  else `.commandFailed(command: command.split(separator:" ").map(String.init), exitCode: code, stderr: stderr)`.
- `.decodingFailed(msg)` → `.unknown(message: msg)`.
- `import CapsuleBackend` added to the file (Diagnostics already may not; allowed —
  Diagnostics→Backend is fine since Diagnostics is above Domain which imports Backend).
  NOTE: verify `CapsuleDiagnostics` target can import `CapsuleBackend`; if not declared,
  add `CapsuleBackend` to its deps in `Package.swift`.

- [ ] **Step 1:** Failing tests: `nonZeroExit` with stderr "Connection refused" →
  `.daemonUnavailable`; with stderr "no such image" → `.commandFailed` (command split,
  code preserved); `executableNotFound` → `.daemonUnavailable`; `decodingFailed` →
  `.unknown`.
- [ ] **Step 2:** Run `swift test --filter ErrorNormalizerTests` → FAIL.
- [ ] **Step 3:** Add `CapsuleBackend` dep to Diagnostics in `Package.swift` if needed;
  implement mapping + `daemonSignature`.
- [ ] **Step 4:** Run → PASS; `make arch` (Diagnostics→Backend must not break guard —
  guard only forbids UI→Backend and Domain→UI/Process, so OK).
- [ ] **Step 5:** `make format`; commit `feat(diagnostics): normalize BackendError incl. daemon/XPC`.

---

### Task 5: Domain health value types + compatibility warning

**Files:**
- Create: `Sources/CapsuleDomain/SystemHealth.swift` (`SystemVersion`, `SystemFeature`,
  `SystemHealth`, `BannerKind`, `compatibilityWarning(client:server:)`).
- Test: `Tests/CapsuleUnitTests/SystemHealthTests.swift`

**Interfaces — Produces:**
- `struct SystemVersion: Sendable, Equatable { var client: String; var server: String? }`
- `enum SystemFeature: String, Sendable, CaseIterable, Codable { case system, containers,
  images, volumes, networks, registries, machines, builder, logsFollow }`
- `enum BannerKind: Sendable, Equatable { case healthy, caution, unhealthy, info }`
- `enum SystemHealth: Sendable, Equatable { case unknown; case checking;
  case running(version: SystemVersion, features: Set<SystemFeature>); case stopped;
  case unavailable(ErrorDetail) }` with `var isRunning: Bool`, `var bannerKind: BannerKind`.
- `func compatibilityWarning(forClient client:String, server:String?) -> String?` —
  returns a string when `SemanticVersion(parsing: client) < minimum` (but minimum lives
  in Backend; redefine the floor here as `SystemVersion`-level: parse via a small
  domain `parseMajorMinorPatch` or reuse by importing Backend — Domain imports Backend,
  so reuse `SemanticVersion` + `BackendCapabilities.minimumSupportedClient`). Mismatch
  rule: client below minimum → "Capsule requires container CLI 1.0.0 or newer…"; server
  present with different major than client → "CLI and service versions differ…".

- [ ] **Step 1:** Failing tests: `running.bannerKind == .healthy`,
  `stopped.bannerKind == .unhealthy`, `unavailable(_).bannerKind == .unhealthy`,
  `unknown.bannerKind == .info`; `compatibilityWarning(forClient:"0.9.0",server:nil)`
  non-nil; `(forClient:"1.0.0",server:"1.0.0")` nil.
- [ ] **Step 2:** Run `swift test --filter SystemHealthTests` → FAIL.
- [ ] **Step 3:** Implement (import `CapsuleBackend` to reuse `SemanticVersion`).
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(domain): system health value types + compatibility warning`.

---

### Task 6: SystemStatusModel state machine

**Files:**
- Create: `Sources/CapsuleDomain/SystemStatusModel.swift`
- Test: `Tests/CapsuleUnitTests/SystemStatusModelTests.swift`

**Interfaces — Produces:**
`@MainActor @Observable final class SystemStatusModel` with:
- `init(backend: any ContainerBackend, normalize: @escaping @Sendable (any Error) -> CapsuleError = { ($0 as? CapsuleError) ?? .unknown(message: String(describing: $0)) }, onActivity: @escaping (String) -> Void = { _ in })`
- `private(set) var health: SystemHealth = .unknown`
- `var compatibilityWarning: String?` (set during refresh)
- `func refreshStatus() async` — sets `.checking`; `try systemStatus()`; if `.stopped`
  → `health = .stopped`; if `.running` → `try version()` + `capabilities()`, map to
  `SystemVersion` + `Set<SystemFeature>` (map `BackendFeature`→`SystemFeature` by
  rawValue), set `.running(...)`, compute `compatibilityWarning`. On throw →
  `health = .unavailable(normalize(error).detail)`.
- `func startServices() async` — `try startSystem()` then `await refreshStatus()`; on
  throw → `.unavailable(normalize(error).detail)`.
- `func stopServices() async` — `try stopSystem()` then `refreshStatus()`.
- Map helper `SystemFeature(backend: BackendFeature)` by rawValue (identical names).

- [ ] **Step 1:** Failing tests using `MockBackend`: after `refreshStatus()` on a
  running mock → `health.isRunning == true` and features non-empty; on a stopped mock
  (`systemRunState:.stopped`) → `health == .stopped`; on `failure = .nonZeroExit(...)`
  with daemon stderr + an injected `ErrorNormalizer.normalize` → `.unavailable`;
  `startServices()` on a stopped mock flips health to running.
- [ ] **Step 2:** Run `swift test --filter SystemStatusModelTests` → FAIL.
- [ ] **Step 3:** Implement the model.
- [ ] **Step 4:** Run → PASS; `swift build`.
- [ ] **Step 5:** `make format`; commit `feat(domain): SystemStatusModel state machine`.

---

### Task 7: UI — ShellState, colors, sidebar sections, availability mapping

**Files:**
- Create: `Sources/CapsuleUI/ShellState.swift`, `Sources/CapsuleUI/SidebarSection.swift`,
  `Sources/CapsuleUI/CapsuleColors.swift`
- Test: `Tests/CapsuleUnitTests/SidebarSectionTests.swift`

**Interfaces — Produces:**
- `enum SidebarSection: String, CaseIterable, Identifiable, Sendable { case containers,
  images, volumes, networks, machines, system }` with `title`, `symbolName`,
  `requiredFeature: SystemFeature?` (system→nil i.e. always enabled), and
  `func isEnabled(features: Set<SystemFeature>) -> Bool`.
- `@MainActor @Observable final class ShellState { var selection: SidebarSection =
  .containers; var inspectorPresented = true; var activityPanePresented = true;
  var activityTab: ActivityTab = .logs }` + `enum ActivityTab { case logs, tasks, progress }`.
- `enum CapsuleColors { static func banner(_ kind: BannerKind, contrast:
  ColorSchemeContrast) -> Color; static let success/caution/error/surface … }` using
  asset-free dynamic `Color` (system colors + opacity, boosted on `.increased`).

- [ ] **Step 1:** Failing `SidebarSectionTests`: `.containers.isEnabled(features:[])`
  false; `.isEnabled(features:[.containers])` true; `.system.isEnabled(features:[])`
  true; `allCases.count == 6`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement the three files (colors compile-only, no test).
- [ ] **Step 4:** Run → PASS; `make arch` (UI must not import Backend — these only
  import CapsuleDomain + SwiftUI).
- [ ] **Step 5:** `make format`; commit `feat(ui): shell state, sidebar sections, semantic colors`.

---

### Task 8: UI — health banner, content column, inspector, activity pane

**Files:**
- Create: `Sources/CapsuleUI/SystemHealthBanner.swift`,
  `Sources/CapsuleUI/ContentColumnView.swift`, `Sources/CapsuleUI/InspectorView.swift`,
  `Sources/CapsuleUI/ActivityPaneView.swift`, `Sources/CapsuleUI/SystemDetailView.swift`
- Test: `Tests/CapsuleUnitTests/BannerPresentationTests.swift`

**Interfaces — Produces:**
- `struct SystemHealthBanner: View` taking `health`, `compatibilityWarning`, and an
  `onRecover: (RecoveryAction) -> Void` closure. Renders title/explanation + recovery
  buttons; pure helper `bannerText(for: SystemHealth, warning: String?) -> (title:
  String, message: String, kind: BannerKind)` is what the test targets.
- `struct ContentColumnView: View` taking `section`, `health`, `workspaceLoadState`,
  `onRecover` — when `!health.isRunning` shows `ContentUnavailableView` with the
  `ErrorDetail`/stopped message + recovery buttons, else the resource placeholder.
- `InspectorView`, `ActivityPaneView` (segmented Logs/Tasks/Progress + reserved
  terminal slot), `SystemDetailView` (version rows + Start/Stop + Export Diagnostics).

- [ ] **Step 1:** Failing `BannerPresentationTests` on `SystemHealthBanner.bannerText`:
  `.stopped` → title contains "stopped"/"not running", kind `.unhealthy`; `.running`
  with a server → kind `.healthy`, message contains the client version; warning
  non-nil overrides kind to `.caution` when running.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement the five views (logic in `bannerText`).
- [ ] **Step 4:** Run → PASS; `make arch`.
- [ ] **Step 5:** `make format`; commit `feat(ui): health banner, content column, inspector, activity pane`.

---

### Task 9: UI — AppShellView + Onboarding

**Files:**
- Create: `Sources/CapsuleUI/AppShellView.swift`, `Sources/CapsuleUI/OnboardingView.swift`
- Modify: `Sources/CapsuleUI/RootView.swift` (delegate to `AppShellView`)
- Test: compile via build (views); keep `RootView(model:)` init source-compatible by
  adding an overload `RootView(systemModel:workspaceModel:shell:)`.

**Interfaces — Produces:**
- `struct AppShellView: View` — `NavigationSplitView { SidebarView } detail:
  { VStack { SystemHealthBanner; ContentColumnView; ActivityPaneView } }`, `.inspector(
  isPresented:)` with `.inspectorColumnWidth(min:240, ideal:320, max:420)`, toolbar
  toggle for inspector + activity pane, `.task { await systemModel.refreshStatus() }`.
- `SidebarView` (inline or its own file) listing `SidebarSection` with enablement.
- `struct OnboardingView: View` — welcome/CLI-check/Start Services, dismiss writes
  `@AppStorage("capsule.hasCompletedOnboarding") = true`.
- `RootView` keeps `public init(model:)` (legacy) AND gains the multi-model init; the
  app uses the new one.

- [ ] **Step 1:** Build only (no unit test) — wire views; ensure `make build`.
- [ ] **Step 2:** `make arch` + `make build` green.
- [ ] **Step 3:** `make format`; commit `feat(ui): NavigationSplitView shell + onboarding`.

---

### Task 10: CapsuleApp — composition, scene, menu bar

**Files:**
- Modify: `Sources/CapsuleApp/AppEnvironment.swift` (build `SystemStatusModel` with
  `ErrorNormalizer.normalize`), `Sources/CapsuleApp/CapsuleScene.swift` (render
  `AppShellView`, present onboarding), `Sources/CapsuleApp/CapsuleCommands.swift` (View
  + Resource menus).
- Test: `Tests/CapsuleUnitTests/CompositionTests.swift` (extend: env builds a
  `SystemStatusModel`).

**Interfaces — Produces:**
- `AppEnvironment.systemModel: SystemStatusModel`; `.live()` injects
  `ErrorNormalizer.normalize` and an activity sink (logs via `Log.ui`).
- `CapsuleScene` holds `systemModel`, `workspaceModel`, `ShellState`; body renders
  `AppShellView`; `.commands { CapsuleCommands(updater:, shell:, systemModel:) }`.
- `CapsuleCommands` adds `CommandGroup`s for View toggles + a `CommandMenu("Resource")`
  with Refresh / Start Services / Stop Services + disabled "Command Palette…" hook.

- [ ] **Step 1:** Failing `CompositionTests`: `AppEnvironment.live().systemModel` exists
  and starts `.unknown`.
- [ ] **Step 2:** Run `swift test --filter CompositionTests` → FAIL.
- [ ] **Step 3:** Implement env + scene + commands.
- [ ] **Step 4:** Run → PASS; `make build`.
- [ ] **Step 5:** `make format`; commit `feat(app): compose system model + menu bar`.

---

### Task 11: Full verification

- [ ] **Step 1:** `make ci` → all green (build zero-warning, lint --strict, arch,
  headers, tests).
- [ ] **Step 2:** `make app` → builds the .app.
- [ ] **Step 3:** Launch (`make run`) and visually confirm: split-view shell; stopped →
  unhealthy banner + Start Services; running → version + healthy; inspector
  toggles/resizes; activity pane present; light/dark/increased-contrast render.
- [ ] **Step 4:** Update memory (`capsule-milestone4-done.md` + `MEMORY.md`).
- [ ] **Step 5:** Final commit if anything uncommitted.

---

## Self-Review

- **Spec coverage:** split-view shell (T9), sidebar (T7/T9), inspector + width (T9),
  activity pane (T8/T9), onboarding (T9), health banner wired to status+version (T6/T8),
  Start/Stop Services (T1–T3,T6,T10), daemon-down ≠ empty (T4,T6,T8), XPC detection
  (T4), menu bar (T10), command-palette hook (T10), capability flags + compat warning
  (T5,T6,T8), dark/contrast colors (T7). All covered.
- **Placeholders:** none — signatures and key logic are concrete.
- **Type consistency:** `SystemRunState`, `SystemHealth`, `SystemFeature`,
  `SystemStatusModel`, `SidebarSection`, `ShellState`, `BannerKind` used consistently
  across tasks; `SystemFeature` mirrors `BackendFeature` by rawValue.
