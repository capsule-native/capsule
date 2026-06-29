# Milestone 10 · System surface — Design

**Date:** 2026-06-30
**Branch:** `milestone-10-system-surface`
**Phase:** 3 (Systems surface), following M9 (Machines), M8 (Volumes/Networks/DNS).

## Goal

Finish the systems layer with four read/insight surfaces and two config surfaces, all over
`container system`:

1. **Storage dashboard** (`system df`) — reclaimable vs in-use totals for images/containers/
   volumes, driving cleanup recommendations that link to the existing prune actions.
2. **Service logs** (`system logs`) — a diagnostics log pane integrated with the existing
   logs infrastructure, with an explicit **empty-is-not-failure** warning.
3. **About / Diagnostics** (`system version`) — CLI + server component versions feeding bug
   reports and compatibility warnings.
4. **Kernel manager** (`system kernel set`) — local-file and remote-tar (and a safe
   "recommended") kernel install in Advanced Settings, a high-risk action gated behind a
   compatibility warning + recovery guidance.
5. **TOML properties** (`system property list`) — read merged properties into a Settings
   inspector with a TOML viewer/editor, inline validation, change review, and **export**,
   pairing every edit with a persistent **"restart services to apply"** banner. Mutable
   `set`/`get` is gone from the CLI, so Capsule is a viewer/editor/exporter — it never writes
   the live config; *requires-restart* is modeled as explicit UI state.

## Ground truth: the real `container system` CLI (v1.0.0, probed live 2026-06-30)

| Subcommand | Shape | Notes |
|---|---|---|
| `system df [--format json\|table\|yaml\|toml]` | JSON **object** | keys `containers`/`images`/`volumes`; each `{ active: Int (count), total: Int (count), reclaimable: Int (bytes), sizeInBytes: Int (bytes) }`. **In-use bytes = `sizeInBytes − reclaimable`.** |
| `system version [--format json\|table\|...]` | JSON **array** | `[{ appName, buildType, commit, version }]`. The apiserver element's `version` is a messy full string (`"container-apiserver version 1.0.0 (build: release, commit: ee848e3)"`) — render defensively. |
| `system logs [--follow] [--last <dur>]` | text stream | `--last` accepts `<number>[m\|h\|d]` (default `5m`), **not** a line count. **No id, no `--boot`.** |
| `system kernel set [--arch arm64\|amd64] [--binary <path>] [--tar <path\|URL>] [--recommended] [--force]` | streams progress | `--recommended` downloads+installs a known-good kernel (takes precedence). `--binary` = local kernel file (or archive member with `--tar`). `--tar` = filesystem path **or remote URL** to a tar archive. Writes user-owned `~/Library/Application Support/com.apple.container/kernels/` → **no sudo**. **No `kernel get`/`list`** — current kernel reads from `property list [kernel]`. |
| `system property list [--format toml\|json]` | TOML (default) or JSON | nested sections (`build`,`container`,`dns`,`kernel`,`machine`,`network`,`registry`,`vminit`); mixed value types (Int/String/Bool); empty sections render as empty tables. **Read-only — there is NO `property set` / `property get`.** |

### Resolved scope decisions (confirmed with user)

1. **TOML apply path = export-only + restart banner.** The CLI has no `property set` and no
   user-writable config file is present, so Capsule reads/validates/edits/**exports** TOML
   (via `NSSavePanel`) and shows a persistent "restart services to apply" banner. Capsule
   never writes the live daemon config. (Matches the acceptance wording "exports".)
2. **Navigation = tabs in the System pane.** The three read surfaces (Storage, Service Logs,
   About) become tabs inside the existing M4 `.system` detail; Kernel + Configuration go to a
   new **Advanced** tab in the Settings scene (per the goal, which already places them there).
3. **Kernel set is not privileged and is not really-run in tests.** It writes user-owned
   files, so no sudo handoff is needed (contingency: if the live probe shows otherwise, fall
   back to the M8 DNS `runPrivilegedInTerminal` pattern). The integration probe verifies argv
   + command preview only — it does **not** install a kernel (that would mutate the host).

## Architecture

Mirror the established vertical-slice path across the strict layers
(UI → Domain → Backend port → CLI adapter → MockBackend), enforced by
`ArchitectureGuardTests` (UI imports no Backend module; Domain uses no `Process`). Reuse
existing infrastructure: `LogsModel`/`LogsPaneView` + `LogSource` seam, `TaskCenter`
streaming, the normalized error model (`ErrorNormalizer.normalize → CapsuleError`), the M9
restart-banner pattern, native SwiftUI `.byteCount` formatting, the existing prune actions,
and the existing `DiagnosticBundle` (export diagnostics).

**Already present (reuse, don't rebuild):**
- Prune everywhere: `pruneContainers()` / `pruneImages(all:)` / `pruneVolumes()` on the port +
  CLI + Mock, and `ContainerLifecycleModel.prune()` / `ImageActionsModel.prune(all:)` /
  `VolumeActionsModel.prune()` domain actions with confirmations. The storage dashboard links
  to these (no new prune logic).
- `OutputParser.parseVersion` already decodes the `system version --format json` array via
  `CLIVersionComponent` (`WireModels.swift`) into a paired `BackendVersion`; fixture
  `Tests/CapsuleUnitTests/Fixtures/system-version.json` already holds the real shape. The
  About pane reuses `CLIVersionComponent` and adds a full-array accessor.
- `LogSource` (`LogsModel.swift`) is source-agnostic (`.container`/`.machine`); add `.system`.
- `SystemDetailView` (M4) is the `.system` section host; `.system` is always-available
  (`requiredFeature == nil`), reachable even when the service is stopped.
- `PreferencesView` is a `TabView` (General/Registries/Networking); add an **Advanced** tab.
- DNS privileged handoff (`runPrivilegedInTerminal`) is the fallback model if any system write
  ever needs sudo (not expected for kernel set).

### Layer changes

**Backend port (`ContainerBackend`) — new methods:**
- `systemDiskUsage() async throws -> StorageUsage`
- `systemComponentVersions() async throws -> [ComponentVersion]` (the full array; existing
  `version()` stays for the paired CLI/server `BackendVersion`)
- `systemPropertiesTOML() async throws -> String` (raw `--format toml`, source of truth for
  the viewer/editor/export) and `systemProperties() async throws -> SystemProperties`
  (`--format json`, structured sections for display + current-kernel read-out)
- `fetchSystemLogs(last: String) async throws -> [OutputLine]` and
  `followSystemLogs() -> AsyncThrowingStream<OutputLine, Error>`
- `setKernel(_ config: KernelConfiguration) -> AsyncThrowingStream<OutputLine, Error>`
  (streaming download/install)

**Value types (`BackendResourceTypes.swift`):**
- `StorageUsage { images: CategoryUsage; containers: CategoryUsage; volumes: CategoryUsage }`
  with `CategoryUsage { total: Int; active: Int; sizeInBytes: Int; reclaimable: Int }` and a
  computed `inUseBytes = sizeInBytes - reclaimable`.
- `ComponentVersion { appName: String; version: String; buildType: String; commit: String }`.
- `SystemProperties { sections: [PropertySection] }`, `PropertySection { name: String;
  entries: [(key: String, value: String)] }` (ordered, string-rendered for display).
- `KernelConfiguration { source: KernelSource; arch: KernelArch; force: Bool }` where
  `KernelSource = .recommended | .localBinary(path: String) | .remoteTar(url: String,
  member: String?)`, with `.arguments -> [String]` as the single source of truth for argv.

**CLI adapter (`CLIContainerBackend`) + `CLICommand` + `WireModels` + `OutputParser`:**
- `CLICommand` factories: `systemDiskUsage()` (`system df --format json`),
  `systemVersion()` (already exists for `version()`; add an array path or reuse),
  `systemPropertiesTOML()` (`system property list` default) / `systemPropertiesJSON()`
  (`--format json`), `systemLogs(last:)` / `systemLogsFollow()`, `setKernel(_:)` (built from
  `KernelConfiguration.arguments`).
- Wire records: `CLIDiskUsageRecord` (+ `CLICategoryUsageRecord`), reuse `CLIVersionComponent`,
  `CLIPropertiesRecord` (decode the nested `[String: [String: JSONValue]]`; a small
  `JSONValue` enum or `AnyDecodable` for mixed scalar types, rendered to display strings).
- `OutputParser`: `parseDiskUsage`, `parseComponentVersions`, `parseProperties` (JSON →
  `SystemProperties`). TOML for the editor is taken raw (no parse needed for display/export).
- Reads use `runChecked` + `--format json`; logs follow via the raw stream path; `setKernel`
  via the streaming path (progress lines).

**MockBackend:** in-memory `StorageUsage` sample (mixed reclaimable/active), a
`[ComponentVersion]` sample (CLI + apiserver, incl. a skewed pair to exercise compat
warnings), a `SystemProperties`/TOML sample (incl. a `[kernel]` section), canned system log
lines (and an **empty** variant to exercise empty-is-not-failure), and `setKernel` that
streams a couple of progress lines + records `lastKernelConfiguration`.

**Domain (`CapsuleDomain`) — new models/types:**
- `StorageDashboardModel` (`@MainActor @Observable`): `loadState`, `usage: StorageUsage?`,
  derived per-category + grand-total in-use/reclaimable, `recommendations:
  [CleanupRecommendation]` (one per category with `reclaimable > 0`, carrying the category +
  reclaimable bytes), `refresh()`. Holds closures to invoke the existing prune actions
  (`reclaimImages`/`reclaimContainers`/`reclaimVolumes`) injected from the composition root so
  Domain doesn't depend on the other actions models directly.
- `AboutModel` (`@MainActor @Observable`): `components: [ComponentVersion]`,
  `compatibilityWarnings: [String]` (e.g. CLI vs apiserver version skew), `bugReportText`
  (versions + OS + Capsule app version), `refresh()`; "Export Diagnostics" reuses the
  existing `DiagnosticBundle` path.
- `KernelManagerModel` (`@MainActor @Observable`): `currentKernel` (from
  `systemProperties()[kernel]`), a `KernelDraft` (source mode, path/url/member, arch, force),
  `validate()` + `validationMessage`, `commandPreview`, `recoveryGuidance` (static copy),
  `install()` via `TaskCenter.runStreaming(kind: .systemKernelInstall, …)`; a
  `confirmation`/pre-flight compatibility-warning gate before install.
- `SystemPropertiesModel` (`@MainActor @Observable`): `toml: String` (loaded merged config),
  `sections: [PropertySection]`, an `editBuffer: String`, `validate() -> [TOMLIssue]` (parse
  errors w/ line info), `changeReview` (keys added/removed/changed vs current via parsed
  tables), `export()` (returns the buffer for an `NSSavePanel`), and `restartRequired: Bool`
  (set true after any edit/export — the explicit requires-restart UI state).
- `CleanupRecommendation { category: StorageCategory; reclaimableBytes: Int }`.
- Service logs reuse `LogsModel` via a new `LogSource.system(_ backend:)`; the System Logs tab
  drives a duration range (5m / 1h / 1d) + follow toggle. The duration threads through the
  seam additively (a `last: String?` parameter on the system source, or the system source's
  closures capture the range) — container/machine sources are untouched.

**TOML parsing dependency:** validation + change-review need to parse the user's edited TOML.
Add a pure-Swift TOML library to `CapsuleDomain` (lead candidate **`TOMLDecoder`**; final pick
verified against the build in the plan, preferring pure-Swift with parse-error/line reporting
and no C++ interop). Used only for parse/validate/diff — Domain stays `Process`-free.

**UI (`CapsuleUI`):**
- Restructure `SystemDetailView` into a `TabView`: **Overview** (existing health/status/
  start-stop/export-diagnostics, unchanged) + **Storage** (`StorageDashboardView`) +
  **Service Logs** (`ServiceLogsView`) + **About** (`AboutDiagnosticsView`). Sidebar `.system`
  row unchanged.
- `StorageDashboardView`: three category cards (Images/Containers/Volumes) each showing total
  size, in-use, reclaimable (bytes + %), a grand-total summary, and **"Reclaim …" buttons**
  that invoke the linked prune actions (through their existing confirmation sheets). Native
  `.byteCount(style: .file)` formatting. Service-down → existing unavailable state.
- `ServiceLogsView`: `LogsPaneView` bound to `LogsModel(source: .system)` + a duration range
  control + follow toggle + a persistent **info banner**: "Empty logs can be normal — some
  startup modes write only to files." Empty is shown as informational, never as failure.
- `AboutDiagnosticsView`: component table (CLI + apiserver: version/build/commit), OS +
  Capsule version, compatibility warnings, **"Copy bug report"** and **"Export Diagnostics"**
  (reusing `DiagnosticBundle`).
- `PreferencesView` → new **Advanced** tab, gated `.disabled(!systemHealth.supports(.system))`,
  containing:
  - **Kernel** section: current kernel read-out + **"Change Kernel…"** → `KernelSetupSheet`
    (source picker: Recommended (safe) / Local file via `NSOpenPanel` / Remote tar URL; arch;
    force; **compatibility warning + recovery guidance**; live command preview; Install runs
    as a streaming `TaskCenter` task, sheet dismisses, progress in Activity).
  - **Configuration** section: inline TOML viewer + **"Edit Configuration…"** → a dedicated,
    larger editor sheet/window (the 520×420 Settings frame is too small for editing): editable
    TOML, inline validation (parse errors), change review (changed keys), **Export** via
    `NSSavePanel`, and a persistent **"restart services to apply"** banner once edited/exported.

**TaskCenter:** add `OperationKind.systemKernelInstall` (+ its title/symbol switch arms).

## Headline behaviors (the GUI-beats-CLI moments)

- **Storage → cleanup links.** The dashboard turns `system df` numbers into action: per
  category it shows what's reclaimable and a one-click path to the matching prune, so "you can
  free 975 MB of images" is actionable, not just informational.
- **Service logs → empty-is-not-failure.** A first-class info banner distinguishes "no logs
  because the service logs to files" from "something is broken". Empty renders calm and
  explained.
- **About → bug report.** One button assembles a paste-ready report (component versions +
  build/commit + OS + Capsule version + diagnostics), and surfaces CLI/server version skew as
  a compatibility warning.
- **Kernel → warn before you break boot.** A high-risk action is fronted by a compatibility
  warning and recovery guidance ("an incompatible kernel can stop containers/machines from
  booting — restore with **Recommended** or `container system kernel set --recommended`")
  before anything downloads/installs.
- **TOML → requires-restart as explicit state.** Edits never silently apply; the model holds
  `restartRequired` and a persistent banner makes the "edit config, then restart the daemon"
  workflow obvious, with inline validation and a change review before export.

## Cross-cutting

- **Gating.** Storage/Logs/About live under the always-available `.system` section, but each
  data panel gates on service-running (`health.supports(.system)`): daemon-down shows the
  existing unavailable state, never empty-as-failure. The Advanced Settings tab is
  `.disabled(!health.supports(.system))`.
- **Errors.** Every call routes through `ErrorNormalizer.normalize → CapsuleError`. Kernel
  install failures surface in the Activity task (`.failed`) with the normalized message +
  recovery guidance.
- **Composition root.** Construct `StorageDashboardModel`, `AboutModel`, `KernelManagerModel`,
  `SystemPropertiesModel` (and the `.system` `LogsModel`) in `AppEnvironment.live()` (wiring
  `normalize`, `onActivity`, `taskCenter`, and the prune-action closures for the dashboard);
  thread through `CapsuleScene → RootView → AppShellView` (System tabs) and into
  `PreferencesView` (Advanced tab). Optional View-menu hooks (Storage / Service Logs) are a
  nice-to-have, not required by acceptance.

## Testing

- **Parser unit tests** with captured fixtures: `system-df.json`, reuse `system-version.json`,
  `property-list.json` (+ a TOML fixture for the editor/validation). Assert `parseDiskUsage`
  (counts vs bytes, in-use computation), `parseComponentVersions` (array incl. the messy
  apiserver string), `parseProperties` (nested mixed-type sections).
- **Adapter argv tests** via `StubProcessRunner`: exact argv for `system df --format json`,
  `system version --format json`, `system property list` (+`--format json`),
  `system logs --last <dur>` / `--follow`, and `setKernel` for each source
  (`--recommended` / `--binary` / `--tar` + `--arch` / `--force`).
- **Domain-model tests** via `MockBackend`: storage totals + recommendations (incl. zero-
  reclaimable → no recommendation); About versions + compatibility warning on skew + bug-report
  text; properties load/validate (well-formed vs broken TOML)/change-review/export; kernel
  draft validation + `commandPreview` per source + recovery-guidance presence;
  `restartRequired` flips on edit; `LogSource.system` (container/machine sources unchanged);
  empty-system-logs variant.
- **One gated live integration probe** (`CAPSULE_INTEGRATION=1`): `system df`, `system version`,
  `system property list` (toml + json), and `system logs --last 5m` reads against the real CLI,
  capturing/locking fixtures. **Kernel set is verified read-only** (argv + preview), not run.
- **Architecture guard** green (UI imports no Backend; Domain no `Process`); `make ci` green;
  `.app` builds/links/signs; a live interactive GUI smoke of the headline flows.

## Plan phasing (for the implementation plan)

1. Port methods + value types + MockBackend + CLI adapter/`CLICommand`/`WireModels`/
   `OutputParser` for df, version-array, property (toml+json), system-logs, kernel-set.
2. Storage dashboard (model + recommendations + view + prune-action wiring).
3. Service logs (`LogSource.system` + `ServiceLogsView` + range/follow + empty-warning).
4. About / Diagnostics (model + view + bug report + diagnostics export reuse).
5. `SystemDetailView` → TabView restructure + composition-root wiring for the System tabs.
6. Kernel manager (Advanced tab + `KernelSetupSheet` + streaming install + `OperationKind`
   + compatibility warning/recovery guidance).
7. TOML properties (add TOML dep + viewer + editor sheet + validation + change review +
   export + restart-required banner).
8. Live wire-shape probe + integration test + whole-branch adversarial review + GUI smoke.

## Non-goals (YAGNI)

- No programmatic `property set` / live-config write (CLI can't); export-only.
- No real kernel install in tests (host-mutating); argv/preview verification only.
- No command palette (M11 owns it).
- No bespoke byte formatter (use native `.byteCount`).
- No log persistence beyond the existing transcript copy/export.
