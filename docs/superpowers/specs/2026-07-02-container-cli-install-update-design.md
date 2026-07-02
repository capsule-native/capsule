# Container CLI install & update — design

**Date:** 2026-07-02
**Status:** Approved (autonomous-mode goal; decisions taken per standing directive)

## Problem

Capsule assumes the `container` CLI exists. When the binary is missing,
`CLIProcessRunner` does raise `BackendError.executableNotFound`, but
`ErrorNormalization` collapses it into `CapsuleError.daemonUnavailable`, so the UI
shows the same "services unavailable" story as a stopped daemon and offers no way
to install. There is also no way to update an installed CLI from the app, even
though Apple ships an updater script at `/usr/local/bin/update-container.sh` with
the `container` pkg.

Goals:

1. Detect "CLI not installed" as a first-class state, distinct from "daemon down".
2. When missing, let the user install the **latest signed** `apple/container`
   release from GitHub.
3. Add an **Update container** button on the System screen that drives
   `/usr/local/bin/update-container.sh`.

## Verified facts driving the design

- `update-container.sh` (Apple's, ships with the pkg): refuses to run while the
  service is running (`launchctl` check), fetches
  `api.github.com/repos/apple/container/releases/{latest|tags/VERSION}`, picks the
  signed pkg by name — `container-installer-signed.pkg` **or**
  `container-<tag>-installer-signed.pkg` — falls back to an **interactive** Y/n
  prompt for the unsigned pkg, and runs `sudo installer`. It therefore needs a
  real TTY → Terminal handoff, never in-app `Process`.
- Live release `1.0.0` publishes `container-1.0.0-installer-signed.pkg` (the
  versioned fallback name) and `container-installer-unsigned.pkg` — asset
  selection must try both signed names.
- `CLIProcessRunner` is architecture-guarded as the sole `Process()` user, and
  `ContainerBackend` models "run the resolved `container` binary" — updating the
  binary itself must not be a `ContainerBackend` method.
- Privileged/TTY work already has a proven seam: `runPrivilegedInTerminal`
  closure → `.command` temp script → `NSWorkspace` open in the preferred
  terminal (`AppEnvironment.swift:446-505`, built for DNS in M8).
- `ExecutableLocator` resolves `/usr/local/bin/container`,
  `/opt/homebrew/bin/container`, then `$PATH`; `CLIContainerBackend` falls back
  to the default path when unresolved, so a missing binary surfaces as ENOENT at
  first spawn — the existing status probe already carries the signal we need.

## Approaches considered

1. **Fully in-app install/update** via a privileged helper (`SMAppService`) —
   rejected: a persistent root helper is a large new attack surface and packaging
   burden for two rare operations.
2. **Terminal handoff for everything** — rejected for install: it would
   regenerate Apple's download/verify logic as app-emitted shell; clunky first-run
   UX. Retained for update, where Apple's script is authoritative and interactive.
3. **Hybrid (chosen):**
   - *Install (CLI missing):* in-app GitHub release lookup + signed-pkg download
     as a cancellable Activity task, then open the pkg in **Installer.app**
     (native admin auth; Gatekeeper validates the signature). Never auto-fall
     back to the unsigned pkg.
   - *Update (CLI present):* confirmation sheet → Terminal handoff running
     `container system stop`, then `sudo /usr/local/bin/update-container.sh`,
     then `container system start` on success.
   - If the updater script is missing, the Update button falls back to the
     install flow (the pkg installs over the existing version).

## Design

### 1. Domain: first-class "not installed" state

- New `CapsuleError` case `.cliNotInstalled(message:recovery:)` (shape follows
  existing cases).
- New `RecoveryAction.installContainerCLI` with user-facing title.
- `ErrorNormalization`: map `BackendError.executableNotFound` →
  `.cliNotInstalled` (recovery: `[.installContainerCLI, .openLogs]`) instead of
  `.daemonUnavailable`.
- New `SystemHealth.notInstalled(ErrorDetail)` case. `SystemStatusModel` sets it
  when the normalized probe error is `.cliNotInstalled`; every existing
  `SystemHealth` switch gains an arm (banner, onboarding, menu bar, System
  Overview…).
- Banner copy for `.notInstalled`: "The container CLI is not installed." with an
  install action; onboarding gets a dedicated branch (install button + "Check
  Again") instead of the generic "services are not running" story.

### 2. Release lookup/download port (install flow)

- **Port (CapsuleBackend):** `ContainerReleaseSource` protocol —
  `latestRelease() async throws -> ContainerRelease` (tag + assets) and a
  download returning progress events plus the downloaded file URL
  (`AsyncThrowingStream`, cancellable).
- **Pure asset selection (CapsuleBackend, unit-tested):** pick
  `container-installer-signed.pkg`, else `container-<tag>-installer-signed.pkg`,
  else throw a "no signed package in release <tag>" error. Unsigned assets are
  never selected.
- **Adapter (CapsuleRegistryClient):** `GitHubReleaseClient` — `URLSession`
  against `api.github.com/repos/apple/container/releases/latest`; download via
  `URLSession` with byte-progress events. This widens the module's charter from
  "Docker Hub search" to "external HTTP adapters"; README/CLAUDE.md wording
  updated accordingly. No new module, no new dependency edges.
- **Mock (CapsuleBackend):** `MockContainerReleaseSource` with seedable release
  + scripted progress, used by unit tests and `CAPSULE_UITEST` mode.

### 3. Domain model: `ContainerCLIUpdateModel`

One `@Observable` model consumed by both Onboarding and System ▸ About:

- Dependencies (injected): `ContainerReleaseSource`, `TaskCenter`, installed
  version provider (from `systemComponentVersions()` via `AboutModel`'s data or
  the backend), `updaterScriptExists: () -> Bool`,
  `openInstaller: @MainActor (URL) -> Void`,
  `runUpdaterInTerminal: @MainActor (String) -> Void` (script text → Terminal
  handoff; mirrors `DNSModel`'s closure seam).
- `checkLatest()` → publishes `latestVersion` / failure detail.
- `installLatest()` → registers a `TaskCenter` streaming task
  (`OperationKind.cliInstall`, cancellable, progress from download events);
  on success calls `openInstaller(pkgURL)`.
- `runUpdater()` → if `updaterScriptExists()` hand off the update script,
  else fall back to `installLatest()`.
- Update handoff script (pure function, unit-tested for exact text, like
  `privilegedTerminalScript`):

  ```sh
  #!/bin/sh
  "<containerPath>" system stop
  sudo /usr/local/bin/update-container.sh && "<containerPath>" system start
  ```

  (`stop` is best-effort — the script re-checks via launchctl; `start` only
  after a successful update.)

### 4. UI

- **Onboarding:** when `health == .notInstalled` — explanation, latest-version
  line (once fetched), **Install container…** (starts the download task; the
  Activity pane shows progress; Installer.app opens when done), **Check Again**
  (re-probe after the user finishes Installer).
- **System ▸ About (`AboutDiagnosticsView`):** a "Container CLI" section showing
  installed version (already known from Components), latest available version /
  "Up to date", and **Update container…**. The button opens a confirmation sheet
  (M11 pattern: what will happen + faithful raw command preview of the handoff
  script) before the Terminal handoff. Disabled while health is `.checking`.
- New `OperationKind.cliInstall` ("Download container installer") with title +
  SF Symbol arms.

### 5. Composition root (CapsuleApp)

- Construct `GitHubReleaseClient` for live mode, `MockContainerReleaseSource`
  for `uiTest()`/previews.
- Provide the closures: `openInstaller` = `NSWorkspace.shared.open(pkgURL)`;
  `runUpdaterInTerminal` = existing `.command`-script + preferred-terminal
  mechanism (generalized, if needed, to accept arbitrary script text alongside
  the current sudo-argv form); `updaterScriptExists` =
  `FileManager.isExecutableFile(atPath: "/usr/local/bin/update-container.sh")`.
- New `CAPSULE_UITEST_SCENARIO=cliMissing`: `MockBackend` gains a mode where
  `systemStatus()` throws `BackendError.executableNotFound` so the real
  normalization/health path is exercised.

### 6. Error handling

- Release fetch/download failures → normalized `CapsuleError` on the task /
  model detail (offline, rate-limited, asset missing). No signed asset → clear
  message naming the tag; never silently unsigned.
- Download task cancel → existing `TaskState.cancelled` path; partial file
  cleaned up by the adapter.
- Update handoff never parses Terminal output (same contract as DNS): the sheet
  says success/failure is visible in Terminal and the app re-probes status.

### 7. Testing

- **Unit (tiers 1–2):** normalization mapping; `SystemStatusModel` →
  `.notInstalled`; asset-selection matrix (primary/fallback/none/unsigned-only);
  `ContainerCLIUpdateModel` (install task registration, success → openInstaller,
  script-missing fallback, latest/installed comparison); exact update-script
  text; `MockContainerReleaseSource` behavior; MockBackend cliMissing mode;
  architecture-guard still green (no new edges).
- **XCUITest:** `cliMissing` scenario → onboarding shows Install button;
  healthy scenario → System ▸ About shows Update button and its confirmation
  sheet (cancel path only — no Terminal in CI).
- **Manual/live:** real GitHub fetch smoke (network test gated like the
  integration tier), plus GUI smoke of both flows.

## Out of scope

- Auto-checking for CLI updates in the background / notifications.
- Pinning to a specific version (`-v`) from the UI — the script supports it;
  the UI targets latest only.
- Unsigned-package installs.
