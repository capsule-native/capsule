# Milestone 7 · Run, Build, Exec, Logs, Copy + terminal + Activity pane — Design

Status: approved-to-build (autonomous; `/goal` directive). Date: 2026-06-29.
Branch: `milestone-7-run-build-exec-logs-copy` (cut from `main` after M6 merges; if M6 is
still unmerged, branch from `milestone-6-images-registries`).

## 1. Goal & scope

Finish the core daily workflows so most tasks never leave the GUI, and complete the
long-running-task infrastructure. Concretely:

- **Activity task model** (foundation): the `TaskCenter`/`OperationTask` backing built in
  M6 gains **cancel**, **determinate-or-indeterminate progress**, and new task kinds, so
  every long job (build/pull/push/save/load/**export**/**system start**/**run-detached**/
  **copy**) registers a queue entry with a streamed transcript, progress, cancel, and retry.
- **Run**: a Quick Run sheet with a live `container run …` command preview ("Run Inspector"),
  a contextual **Run Image…** from the Images list. Attached/TTY runs open the integrated
  terminal; detached runs register a task. On failure, a triage panel offers
  **resolve image / inspect logs / retry in terminal**.
- **Build**: a Build sheet with **folder drag/drop** for the context dir, presets, a tag,
  optional Dockerfile path and build-args, and a **live streaming pane**. Raw stdout/stderr
  is **never hidden**: the full transcript stays, is exportable, and a **"plain progress"
  retry** re-runs with `--progress plain`.
- **Exec / interactive**: an Exec sheet (`exec -it <id> <cmd>`), a **machine shell**, the
  AppKit-hosted terminal (already built in M5.5), a detachable **"Open in Terminal.app"**
  fallback, and rerun-with-captured-command.
- **Logs**: a logs pane + a **detachable log window** backed by `container logs` with
  follow, **tail (-n)**, **search**, and **save transcript**.
- **Copy**: a copy sheet + drag/drop between a Finder-like host panel and a best-effort
  container file browser, validating `container:path` semantics early with path examples.

Out of scope (YAGNI): `create` (run covers the common path); env-file/secret-file pickers
for build (`--build-arg`/typed env rows are enough); a full recursive container file tree
(one-level `ls` listing on demand is enough); progress bars parsed from every CLI line
(determinate only where the CLI emits a clean `NN%`, indeterminate otherwise — the
transcript stays the source of truth, per M6 decision #4).

## 2. CLI facts (verified against `container` v1.0.0 `--help` on this machine)

```
run   [opts] <image> [args...]
        -e/--env key=value     -i/--interactive   -t/--tty   -w/--workdir <dir>
        -d/--detach            --name <name>       --rm/--remove
        -p/--publish [host-ip:]host-port:container-port[/proto]
        -v/--volume <volume>   --mount type=,source=,target=,readonly
        -u/--user <user>       --entrypoint <cmd>  --platform <os/arch>
        --progress auto|none|ansi|plain|color
build [opts] [<context-dir>]   (context default: ".")
        -t/--tag <name>        -f/--file <path>    --build-arg key=val   --no-cache
        --progress auto|plain|tty   --target <stage>   -l/--label   --platform
        (NB: default --tag is a random UUID, so we require a tag in the sheet)
exec  [opts] <container-id> <args...>
        -i/--interactive  -t/--tty  -w/--workdir  -e/--env  -u/--user  -d/--detach
copy  <source> <destination>   (alias: cp; <source>/<dest> are container:path or local path)
logs  [--boot] [-f/--follow] [-n <n>] <container-id>
machine run [-i -t] [-n <name>] [<executable>] [args...]   (default executable: login shell)
```

No native "list files inside a container" verb exists, so the container file browser issues
`container exec <id> ls -la <path>` and parses the output leniently (best-effort; requires a
running container with `ls`). The `cp` alias resolves to the canonical `copy` subcommand —
the adapter emits `copy`.

## 3. Architecture & layering

Obeys the arch-guard rules (UI imports no Backend; Domain imports no UI and no `Process`).
Reuses every M5.5/M6 seam: the `TaskCenter` for long jobs, the `TerminalRequest` +
`TerminalSurfaceProviding` port for interactive sessions, and the per-view `Sheet` enum +
`.sheet(item:)` presentation pattern.

### 3.1 Backend port additions (`CapsuleBackend.ContainerBackend`)

New value types (pure data, in `CapsuleBackend`, each with a computed `arguments: [String]`
— the argv **after** `container` — so the CLI adapter and the Domain's terminal-request
builder share one source of truth and both are unit-tested):

```swift
struct RunConfiguration: Sendable, Equatable {
    var image: String
    var name: String?
    var command: [String]            // init-process args after the image
    var env: [String]                // ["KEY=value", …]
    var publishPorts: [String]       // ["8080:80", "127.0.0.1:5432:5432/tcp", …]
    var volumes: [String]            // ["/host:/container", "vol:/data:ro", …]
    var workdir: String?
    var user: String?
    var interactive: Bool            // -i
    var tty: Bool                    // -t
    var detach: Bool                 // -d
    var remove: Bool                 // --rm
    var arguments: [String] { … }    // ["run", "-d", "--rm", "--name", …, image, cmd…]
}
struct BuildConfiguration: Sendable, Equatable {
    var contextDirectory: URL
    var tag: String
    var dockerfile: String?          // -f
    var buildArgs: [String]          // ["KEY=value", …]  (--build-arg)
    var noCache: Bool
    var plainProgress: Bool          // --progress plain  (the "plain retry")
    var arguments: [String] { … }    // ["build", "--tag", …, "--progress", "plain"?, ctx]
}
struct ContainerFileEntry: Sendable, Equatable, Identifiable {
    var name: String; var isDirectory: Bool; var size: Int64?; var mode: String?
    var id: String { name }
}
```

New protocol methods:

```swift
// Run (detached only goes through the port; interactive run is a TerminalRequest)
func runContainer(_ config: RunConfiguration) async throws -> String   // returns the new id
// Build (streaming; transcript is the source of truth)
func buildImage(_ config: BuildConfiguration) -> AsyncThrowingStream<OutputLine, Error>
// Copy (one-shot; either source or destination is container:path)
func copyToContainer(source: URL, containerID: String, containerPath: String) async throws
func copyFromContainer(containerID: String, containerPath: String, destination: URL) async throws
// Logs (non-follow fetch; followLogs already exists for the follow case)
func fetchLogs(container id: String, tail: Int?, boot: Bool) async throws -> [OutputLine]
// Container FS listing for the copy browser (best-effort via `exec ls`)
func listContainerDirectory(id: String, path: String) async throws -> [ContainerFileEntry]
```

`CLICommand` gains a static factory per command (delegating to `config.arguments` for
run/build); `CLIContainerBackend` implements one-shot ops via the existing `runChecked` and
streaming ops via `runner.stream`. `runContainer` captures stdout and returns the trimmed
last non-empty line (apple/container prints the new id on `run -d`). `listContainerDirectory`
runs `exec <id> ls -la <path>` through the non-throwing `runRaw` escape hatch and parses
rows leniently (graceful empty/`unavailable` on a non-running container). `MockBackend`
gains in-memory implementations that record last-call params and honor `failure` injection;
build/copy reuse the seeded-stream / state-mutation patterns.

### 3.2 Activity task model (`CapsuleDomain`)

- `TaskState` gains **`case cancelled`** (`isActive == false`; rendered neutral/gray, not
  red — a cancel is not a failure).
- `OperationKind` gains **`build`, `run`, `export`, `systemStart`, `copy`** (existing:
  pull/push/save/load) with titles + SF symbols.
- `OperationTask` gains an optional **`progress: Double?`** surfaced from
  `state == .running(progress:)` (already modelled) and a **`isCancellable`** flag.
- `TaskCenter` gains:
  - `cancel(_ task:)` — cancels the driver `Task`; the streaming backend's
    `AsyncThrowingStream.onTermination`/`CLIProcessRunner` cancellation terminates the child
    process. A cancelled driver sets `state = .cancelled` (catching `CancellationError`).
  - A small `ProgressParser` applied to each streamed line: when a line matches a clean
    `NN%` it updates `state = .running(progress: NN/100)`; otherwise progress stays `nil`
    (indeterminate). Pure + unit-tested; default behavior unchanged for pull/push.
- **Wire export + system start as tasks**: `ContainerLifecycleModel.export` registers a
  `.export` task via the task center (with cancel); `SystemStatusModel.startServices`
  registers a `.systemStart` task. Both keep their existing notices for hard failures.

### 3.3 Domain models (`CapsuleDomain`)

All `@Observable`, constructed in `AppEnvironment.live()` with `backend`, `normalize`,
`onActivity`, and (where relevant) `taskCenter`, `reloadList`, `launchTerminal`/`copyCommand`
seams — mirroring `ImageActionsModel`/`ContainerLifecycleModel`.

- **`RunModel`** — holds a `RunDraft` (UI-friendly raw strings: image, name, port rows, env
  rows, volume rows, workdir, command, toggles). `validatedConfiguration()` parses the draft
  into a `RunConfiguration` or returns field-level `invalidInput` errors. `commandPreview`
  exposes `"container " + config.arguments.joined(" ")` live (the Run Inspector).
  `runDetached()` → `taskCenter.runAsync(.run)` (onSuccess: reload containers) ;
  `runInTerminal()` → builds the interactive `RunConfiguration` (i/t on, detach off) and
  emits a `TerminalRequest(kind: .runInteractive)` through `launchOrCopy`. A failed detached
  run records the failing task and exposes triage actions
  (`resolveImage` → open Pull sheet for the image; `inspectLogs`; `retryInTerminal`).
- **`BuildModel`** — holds a `BuildDraft` (contextDirectory, tag, dockerfile, build-arg rows,
  noCache, preset). `presets` = Default / No-cache / Plain-progress. `build()` →
  `taskCenter.runStreaming(.build)` (onSuccess: reload images). `retryPlain(task:)` re-runs
  the build with `plainProgress = true`. Transcript export = the task's `transcriptText`
  (Save via `NSSavePanel` in the UI). Validates the context dir exists and a tag is present.
- **`LogsModel`** — per-container log viewing: `lines: [LogLine]`, `follow`, `tail: Int?`,
  `boot`, `searchText`, derived `filteredLines`. `start(id:)` runs `followLogs` (follow) or
  `fetchLogs` (snapshot) into the buffer; `stop()` cancels. `transcriptText` for save.
- **`CopyModel`** — `direction` (toContainer/fromContainer), `hostURL: URL?`,
  `containerID`, `containerPath`, derived `validation` (container path must be absolute;
  shows `id:/abs/path` examples; both endpoints required). `copy()` →
  `taskCenter.runAsync(.copy)` calling the matching backend method (onSuccess: notice).
  `browse(path:)` → `backend.listContainerDirectory` for the container panel (best-effort).

### 3.4 UI (`CapsuleUI`)

- **Run**: `QuickRunSheet` (image; name; +/- port/env/volume rows; workdir; command; toggles
  for interactive+tty / detach / remove; a live monospaced **command preview**; Run button
  that routes to terminal or task by the interactive toggle). A **Run Image…** context item +
  toolbar button in `ImageListView` (prefills the image). The failure **triage panel**
  (`RunFailureTriageView`) reads the failed `.run` task and offers Resolve Image / Inspect
  Logs / Retry in Terminal.
- **Build**: `BuildSheet` — a **drop zone** (`onDrop` of a folder `NSItemProvider`, plus a
  Choose… button) for the context dir, a preset `Picker`, tag/Dockerfile fields, +/- build-arg
  rows, a no-cache toggle, a live `TaskTranscriptView` pane while building, an **Export
  Transcript** button, and a **Retry with plain progress** button shown on failure. Reached
  from the Images toolbar (**Build…**).
- **Exec / terminal**: `ExecSheet` (container id read-only; command field defaulting to `sh`;
  interactive+tty toggle; Run → terminal). A **machine shell** action opens an interactive
  login shell in a machine via `container machine run -it [-n <name>]` (a `TerminalRequest`,
  surfaced from the Machines list when that section lands; harmless to wire now). The
  **"Open in Terminal.app"** fallback writes the argv to a temp script and launches
  Terminal via `NSWorkspace`/`open -a Terminal`; offered alongside the existing
  copy-to-clipboard fallback. The terminal tab already supports rerun via its Restart banner;
  rerun-with-captured-command reuses `session.request`.
- **Logs**: `LogsPaneView` (follow toggle, tail field, search field, save button, monospaced
  scrollback) shown in a new **Logs** Activity sub-surface for the selected container, and a
  detachable **`Window`** scene (`LogWindow`) opened via a toolbar/menu **Open Log Window**;
  both bind a `LogsModel`. Save uses `NSSavePanel` (`.txt`/`.log`).
- **Copy**: `CopySheet` — a direction segmented control; a host panel (a drop target + Choose…
  showing the chosen path) and a container panel (id field + path field with inline
  `id:/path` examples and a **Browse** disclosure that lists `ContainerFileEntry` rows from
  `listContainerDirectory`); drag a host file onto the container panel (or vice-versa) to set
  the pair; a Copy button gated on `validation`. Reached from a container's context menu
  (**Copy Files…**).

### 3.5 Composition (`CapsuleApp`)

`AppEnvironment` gains `runModel`, `buildModel`, `logsModel`, `copyModel`; `live()` wires
them with the shared `taskCenter`, `ErrorNormalizer.normalize`, `shell.appendActivity`, the
container/image reloads, and the terminal launch/copy seams (the same closures
`ContainerLifecycleModel` already receives). `runModel`'s interactive path and the new
Open-in-Terminal fallback are injected here (the only place that may touch `NSWorkspace`).
`CapsuleScene` adds a `Window("Logs", id: LogWindow.id)` scene bound to `logsModel` for the
detachable window. `CapsuleCommands` adds a **View ▸ Open Log Window** item.

## 4. Error handling

Every backend failure normalizes through `ErrorNormalizer.normalize` → `CapsuleError` →
`ErrorDetail`, as elsewhere. Raw transcripts stay visible: build/run-detached/copy/export
keep their full task transcript; the run triage panel and build sheet never hide stdout/
stderr. Cancel is a first-class neutral outcome (`.cancelled`), distinct from failure.
Benign cases: copying onto a stopped/missing container surfaces the CLI's verbatim stderr;
`listContainerDirectory` degrades to an "unavailable" notice (running container required)
rather than throwing into the UI. Path validation rejects a missing `:` or relative
container path **before** spawning, with an example.

## 5. Testing (all against `MockBackend`)

- `RunConfigurationTests` / `BuildConfigurationTests` — `arguments` argv for every toggle
  combination matches the verified `--help` flags (detach vs interactive, ports/env/volumes,
  no-cache, plain progress, custom Dockerfile, build-args, context default).
- `CLICommandTests` / `CLIContainerBackendTests` — argv for run/build/copy(to+from)/
  fetchLogs/listContainerDirectory; `runContainer` returns the parsed id; `copy` (not `cp`)
  is emitted; `listContainerDirectory` parses `ls -la` leniently and degrades on non-zero.
- `TaskCenterTests` — `cancel` flips a running task to `.cancelled` and stops the driver;
  `retry` of a cancelled task re-runs; `ProgressParser` updates determinate progress and
  leaves unmatched lines indeterminate; new kinds carry titles/symbols.
- `RunModelTests` — draft→config validation (good + each field error), `commandPreview`,
  detached run registers a `.run` task + reloads, interactive run emits a `TerminalRequest`
  (argv `container run -it …`), triage actions.
- `BuildModelTests` — draft→config, presets, `build()` registers a streaming `.build` task +
  reloads images on success, `retryPlain` sets `--progress plain`, context/tag validation.
- `LogsModelTests` — follow vs snapshot population, search filter, tail/boot flags,
  `transcriptText`, stop cancels.
- `CopyModelTests` — direction argv routing, validation (missing endpoint, relative
  container path, missing `:` handled by the model), `copy()` registers a `.copy` task,
  `browse` lists entries / degrades.
- `MockBackendTests` — new methods mutate/record state and honor `failure`.
- `ArchitectureGuardTests` — unchanged rules keep passing (no UI→Backend, no Domain→Process).
- `CompositionTests` / `AppEnvironmentActionsTests` — env exposes the new models; export and
  system-start now register tasks; a run-detached action registers a task and reloads.

Acceptance maps 1:1 to the goal: build streams live logs with export + plain-progress retry ✓;
run attaches into the integrated terminal with a failure triage panel ✓; exec opens the
AppKit-hosted terminal with detach fallback + rerun ✓; logs follow/search/save ✓; copy
validates paths and supports drag/drop ✓; the Activity pane shows progress, transcript,
cancel, and retry for every long job ✓.

## 6. Decisions log (autonomous; documented for async review)

1. **Interactive run/exec go through the terminal (PTY), not the runner.** Only detached run,
   build, copy, logs-fetch, and ls-listing go through the `ContainerBackend` port; `run -it`
   and `exec -it` are `TerminalRequest`s spawned by `SwiftTermSurfaceProvider`. This avoids
   bolting bidirectional stdin onto `CLIProcessRunner`.
2. **One source of truth for argv.** `RunConfiguration`/`BuildConfiguration` own a computed
   `arguments`; both the CLI adapter and the Domain terminal-request builder consume it.
3. **Cancel is a neutral state (`.cancelled`)**, not a failure — different glyph/color, retry
   still offered.
4. **`run -d` returns the id by parsing stdout** (no machine-readable verb); best-effort.
5. **Container file browser is one-level `exec ls`**, best-effort, requires a running
   container; it degrades gracefully rather than pretending to be a full VFS.
6. **`copy` emitted, not `cp`** (canonical subcommand); both source/dest validated for
   `container:path` before spawning.
7. **Determinate progress only where the CLI emits a clean `NN%`** (pull/build), else
   indeterminate; the transcript stays the source of truth (carries M6 decision #4 forward).
8. **One milestone, one branch**, phased commits (Activity-model → backend → run → build →
   exec → logs → copy → composition/smoke), mirroring M6.
</content>
</invoke>
