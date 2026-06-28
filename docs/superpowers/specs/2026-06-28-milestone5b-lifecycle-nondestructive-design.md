# Milestone 5B · Container lifecycle — non-destructive (start / stop / stats) — Design

_Phase 2 · Core workflows. Date: 2026-06-28. Branch: `milestone-5b-lifecycle`._

## Background & milestone structure

Milestone 5 ("Containers browser, inspector, and lifecycle") is split into independent,
separately-mergeable milestones. 5A (browser + inspector) is merged. The lifecycle work is
further split by destructiveness and terminal-dependence:

| Milestone | Scope |
|---|---|
| **5B (this spec)** | `start` (+ read-only attach interim), `stop` (graceful, timeout/signal options, hang detection + interim Force Stop), `stats` (live pane + compact chips + one-shot snapshot) |
| **5C** | destructive: `kill`/Force-Stop, `delete`/`rm` (single + bulk), `prune` (Cleanup sheet), `export` (save panel) |
| **M6 — Embedded Terminal** | a new `CapsuleTerminal` adapter module + a terminal-session port (libghostty behind a pinned `GhosttyKit.xcframework`, with SwiftTerm as a stable fallback). Flips interactive attach, "exec shell", and "retry in terminal" from interim → real. Its own full spec cycle; lands after 5C. |

This was decided with the user. The embedded terminal is M6 (right after 5C).

### Terminal-dependent interim (until M6)

Every terminal-dependent affordance follows one rule: **never shell out to Terminal.app,
never build a TTY.**

- **"Retry in Terminal"** (`RecoveryAction.retryInTerminal`): copies the exact `container …`
  command (argv from the single `CLICommand` factory, with the executable prepended) to the
  pasteboard and posts an activity-log note. Injected as a composition-root closure, like
  `ErrorNormalizer`/`ScopeStore`.
- **"attach" (`start -a`)**: streams the container's output **read-only** via the existing
  `followLogs` port into a dedicated attach console. `AttachSession.isReadOnly` is hard-coded
  `true`; that flag is the seam M6 flips.
- **"Open Shell" / interactive exec**: rendered where users expect it but **disabled**, gated
  on an injected `terminalAvailable` seam (default `false`), captioned "arrives with the
  embedded terminal update."
- **Force Stop (hang escalation)** — *hybrid, per user decision*: 5B ships hang **detection**
  AND a working interim Force Stop using the non-destructive stop verb (`container stop -t 0`,
  i.e. send signal then kill immediately), so a user is never stuck waiting. It **also** offers
  "Retry in Terminal" copying `container kill <id>`. The **true destructive `kill` Force Stop
  with a confirmation sheet** still lands in 5C and supersedes the interim there.

## Verified CLI facts (container v1.0.0)

- `stop [--all] [-s/--signal <sig>] [-t/--time <sec> default 5] [<ids>…]` — graceful; sends the
  signal then kills after `--time`. `-t 0` ⇒ effectively immediate force via the stop verb.
- `stats [<ids>…] [--format json|table|yaml|toml] [--no-stream]` — JSON is a **JSON array** of
  the source `ContainerStats` struct (verified against apple/container source: keys = property
  names, camelCase, **only `id` required, every metric an optional `UInt64`**, cumulative
  `cpuUsageUsec` — no CPU% and no timestamp in the payload). Empty result = `[]` (verified live).
  `--no-stream` is redundant (any non-table `--format` already takes the one-shot path); include
  it for clarity, do not document it as the disabling mechanism.
- `inspect`/`image inspect` take **no `--format`** (JSON by default). Already fixed & committed
  on this branch; preserved here with its regression test.
- Lifecycle errors (stop/kill/export on a missing container) exit **1** with stderr
  `Error: internalError: "failed to …" (cause: "notFound: …")`.
- `list --format json` exposes **no per-container disk size** (affects 5C prune only).
- **Local-test limitation:** the dev service has no kernel configured, so no container can
  actually run; `runFailed` detection, "already stopped" idempotency, and signal-token
  acceptance are unverified end-to-end and handled leniently / documented best-effort.

## Architecture & layering (unchanged rules)

Ports & Adapters, strictly layered: UI(`CapsuleUI`) → Domain(`CapsuleDomain`) → Backend port
(`CapsuleBackend`); adapter `CapsuleCLIBackend`; composition root `CapsuleApp`. Arch guard:
**`CapsuleUI` imports no Backend module; `CapsuleDomain` imports no UI and no `Foundation.Process`**.
New Backend value types are Foundation-only and **mapped by the domain into domain types before
reaching the UI** — no Backend wire type ever appears in a `CapsuleUI` signature. Domain models
are `@Observable @MainActor` (from `Observation`). All process/argv/poll-loop logic stays in the
adapter; the domain's CPU% math uses `ContinuousClock` (allowed; not `Process`).

## Shared backend port expansion (5B portion)

New value types in `CapsuleBackend` (`BackendLifecycleTypes.swift`):

- `StopOptions { timeout: Int?; signal: String? }` — `signal` is a raw `String` (Backend can't
  import the domain's `ProcessSignal`). `static let `default`` = `StopOptions(timeout: nil, signal: nil)`.
  `static let forced` = `StopOptions(timeout: 0, signal: nil)` (the interim Force Stop).
- `ContainerStatsSample` — all-optional mirror of the source `ContainerStats` (`id` required;
  `cpuUsageUsec`, `memoryUsageBytes`, `memoryLimitBytes`, `networkRxBytes`, `networkTxBytes`,
  `blockReadBytes`, `blockWriteBytes`, `numProcesses` all optional `UInt64`). Carries **no CPU%
  and no timestamp** — the domain computes/stamps both.

Port methods (5B):

- `stopContainer(id:options:)` **replaces** `stopContainer(id:)`. A protocol extension
  `stopContainer(id:)` ⇒ `stopContainer(id:options:.default)` preserves call sites. **Must-fix:**
  delete the old arity-1 concrete methods from both `MockBackend` and `CLIContainerBackend`
  (a concrete arity-1 method would shadow the extension and skip the new options path).
- `containerStats(ids:) -> [ContainerStatsSample]` — one-shot (`stats --no-stream --format json`).
  Domain always passes **explicit running ids**; never relies on "empty ids = all".
- `streamContainerStats(ids:interval:) -> AsyncThrowingStream<[ContainerStatsSample], Error>` —
  adapter polls the one-shot path on `interval`. **Precise lifecycle (must-fix):** store the poll
  `Task`; `continuation.onTermination = { _ in task.cancel() }`; catch `CancellationError` from
  `Task.sleep`/the one-shot call and `finish()` **cleanly** (never `finish(throwing: CancellationError)`);
  real backend errors `finish(throwing:)`; no `yield` after `finish`.

Adapter additions (`CapsuleCLIBackend`):

- `CLICommand.stopContainer(id:options:)` → `["stop"] + (-t timeout?) + (-s signal?) + [id]`;
  `CLICommand.containerStats(ids:)` → `["stats","--no-stream","--format","json"] + ids`.
- `ArgumentBuilder.adding(contentsOf: [String])` (variadic `adding(_:)` can't splat an array).
- `CLIContainerStatsRecord` (internal `Decodable`, no `CodingKeys`) in `WireModels.swift`;
  `OutputParser.parseStats` (lenient list decode → `[ContainerStatsSample]`).
- `CLIProcessRunner`: add **cancellation propagation** to the streaming path (and `run` where it
  backs cancellable awaits) — `withTaskCancellationHandler` + `process.terminate()` — so the stats
  poll's `onTermination` and attach teardown actually reap the child process (must-fix).

`MockBackend`: implement the new methods; add `startFailure`, `logStreamFailure`, a mutable
`startedState`, seeded `sampleStats`, and a **paced** synthetic stream (so the domain CPU% delta
isn't divided by ~0). Remove the old `stopContainer(id:)`.

## 5B domain design

New file `Sources/CapsuleDomain/Lifecycle.swift`:

- `LogLine { id: Int; stream: Stream; text: String }`, `enum Stream { standard, error }`
  (mapped from `OutputLine.source` — which is the **`container logs` CLI process's** pipe, not the
  workload's stdout/stderr; documented honestly).
- `AttachSession { phase: Phase; lines: [LogLine] (ring-buffer capped at 200); isReadOnly == true }`,
  `enum Phase { streaming, ended, failed(ErrorDetail) }`.
- `ContainerStartResult { started(attached: Bool), createdButNotStarted, runFailed,
  failedBeforeExecution, backendUnavailable, interrupted }` — **no `startedAttachmentFailed`**
  (attach failure is a separate channel). `operationStatus` is derived via a `CommandObservation`
  + `OperationStatus.resolve(...)`, not hand-mapped.
- `ContainerMetrics { id; cpuPercent: Double?; memoryUsageBytes/limitBytes/percent; networkRx/Tx;
  blockRead/Write; numProcesses; capturedAt: Date }` (mapped from `ContainerStatsSample`).
- `LifecycleNotice { detail: ErrorDetail; offersShellHint: Bool }`, `StopOutcome`.
- `ContainerState` gains **`.stopping`** (maps the CLI's transitional state; running→running,
  stopped→stopped, stopping→"Stopping…", else→unknown). Stop relying on `created`/`paused` from
  real data.

New model `ContainerLifecycleModel` (`@MainActor @Observable`), keeping `ContainerBrowserModel`
a pure read surface. Injected seams (closures, like `SystemStatusModel`): `normalize`, `onActivity`,
`reloadList`, `currentState(id) -> ContainerState`, `terminalAvailable () -> Bool`,
`copyCommandToTerminal([String])`. Responsibilities:

- **start(id:, attach:)** — calls `backend.startContainer(id:)`:
  - threw → normalize; `failedBeforeExecution`/`backendUnavailable` reported as such; otherwise
    (the container resource pre-exists for `start`) → `createdButNotStarted`.
  - returned → provisional success, then **verify over a short bounded settle window** (`reloadList()`
    + re-check `currentState` a few times across ~1–2 s with a "verifying…" state): running →
    `started`; still-not-running after the window → `runFailed` (**best-effort**, documented; reliable
    detection waits for M6's attached start).
  - **attach** (single-flight): cancel/nil the prior `attachTask`; start `followLogs` pump into
    `AttachSession`; attach failure flows **solely** via `AttachSession.phase = .failed` + a
    `pendingNotice` mapped to `OperationStatus.stateChangedButAttachmentFailed` — start success is
    never hidden/rolled back. Teardown on container deselection and list `onDisappear`.
    `CancellationError` is swallowed (clean). Recovery offers **Retry Attach** + a disabled
    Open-Shell hint (not "Open Logs" — circular).
  - **bulk start** (multi-select): sequential, continue-on-failure, aggregate count to the activity
    log; **attach disabled for multi-select**.
- **stop(id:, options:)** — calls `backend.stopContainer(id:options:)`; races it against a
  **watchdog** (structured concurrency, no busy-wait). Per-container state machine
  `.idle → .stopping → (.stopped | .failed | .hung)`. On `.hung`: a `LifecycleNotice`
  "Stop is taking longer than expected" offering (hybrid):
  - **Force Stop** (enabled in 5B) → `stop(id:, options: .forced)` (`container stop -t 0 <id>`);
  - **Retry in Terminal** → copies `container kill <id>`.
  "Already stopped / not running" is benign (lenient substring match → info note), and **must not**
  collide with `ErrorNormalizer`'s `not running` daemon-signature — intercept it in the domain before
  normalization.
- The interim Force Stop reuses the stop path with `.forced`; 5C will add the real destructive
  `kill` Force Stop (with confirmation) and can supersede the interim button.

New model `ContainerStatsModel` (`@MainActor @Observable`):

- **live**: subscribes to `streamContainerStats(ids:interval:)` with **explicit running ids**;
  early-returns when the running set is empty (never calls with empty ids).
- **snapshot**: `containerStats(ids:)` one-shot.
- **CPU%**: `% = (cpu₂−cpu₁)/elapsedUsec × 100` (100% = one core) from two consecutive samples,
  using `ContinuousClock` arrival stamps recorded in-domain. **Epsilon guard:** emit CPU% only when
  `elapsed > epsilon`, else hold the prior value.
- **clean interrupt restore**: cancel the stream task on deselect/disappear; a test cancels
  mid-stream and asserts no thrown error + the poll loop stops.
- **latency reality (documented):** the one-shot path sleeps ~2 s internally, so effective cadence is
  `interval + ~2 s`; the UI must not promise sub-second ticks.

## 5B UI

Create: `StartAttachSheet`, `LifecycleNoticeView` (routes `.retry` to a **container-scoped** retry,
not the shell's generic `.retry` → `systemModel.refreshStatus()`), `AttachConsoleView` (lines +
read-only badge + Detach + disabled Open-Shell + `.streaming/.ended/.failed` footer; does **not**
overload `ShellState.activityLog`), `StopOptionsSheet` (timeout + graceful signal), `StatsPaneView`,
`StatChips`.

Modify: `ContainerListView` (Start/Stop in toolbar + `contextMenu(forSelectionType:)`, per-row busy
spinner, sheets), `ContainerInspectorView` (stat chips + live pane + snapshot toggle in Summary),
`ActivityPaneView` (render `AttachConsoleView` when attached), `ContentColumnView` / `AppShellView` /
`RootView` (thread both new models).

Composition root (`AppEnvironment` / `CapsuleScene`): construct `ContainerLifecycleModel` +
`ContainerStatsModel`; wire seams incl. the **clipboard** retry-in-terminal interim and
`terminalAvailable: { false }`.

## Safety / messaging (5B)

- Start is **non-destructive** → no confirmation; the only modal is the informational attach sheet.
  Start enabled only for a non-running, non-busy selection; already-running skipped idempotently.
- Stop is non-destructive but offers options + hang escalation; "already stopped" is benign.
- Messaging matrix: `started`/`stopped` → **activity-log line only** (no modal/toast);
  `createdButNotStarted` → "Created but not started" + Try Again (container-scoped) / Retry in
  Terminal / Open Logs; `runFailed` → "Container failed to run" (best-effort) + Try Again / Open Logs;
  attach failure → "Started, but couldn't attach" + Retry Attach + disabled Open-Shell hint (start
  stays successful).
- Every failure routes through `ErrorNormalizer → ErrorDetail` and offers retry-in-terminal
  (interim = copy command).

## Testing (TDD, against `MockBackend`)

- **Backend/CLI:** `CLICommandTests` (stop-with-options argv, stats argv), `ArgumentBuilderTests`
  (`adding(contentsOf:)`), `OutputParserTests` (`parseStats` incl. empty `[]` and lenient/odd
  element), `MockBackendTests` (stop options recorded, stats snapshot/stream, removal of arity-1
  stop), `CLIProcessRunnerTests` (cancellation reaps the child).
- **Domain:** `ContainerLifecycleModelTests` — start success/created-vs-runFailed via settle window,
  attach single-flight + ring-buffer cap + clean cancel, bulk start continue-on-failure, stop
  state machine incl. `.hung` → interim Force Stop (`.forced` issued), "already stopped" benign,
  retry-in-terminal copies the right argv; `ContainerStatsModelTests` — CPU% delta, epsilon guard,
  empty-ids no-op, clean interrupt restore.
- **UI:** logic lives in the models (headless-testable); views verified by build + inspection,
  consistent with 5A. Arch guard + `make ci` stay green.

## Acceptance (5B)

- `start` works from toolbar/menu/context-menu; optional attach streams read-only output into a
  dedicated console; **"created but not started" is distinguished from "run failed"** in messaging;
  attach failure keeps start success visible and offers Retry Attach + (disabled) Open Shell.
- `stop` works with timeout/signal options; a hung stop is detected and offers a working interim
  Force Stop (`stop -t 0`) plus a `container kill` clipboard copy.
- `stats` shows live metrics (pane + compact chips) and a one-shot snapshot; CPU% is computed
  correctly; streaming restores cleanly on interrupt with no leaked tasks/processes.
- Every failure routes through the normalized error model with a retry-in-terminal (clipboard)
  path; success is reported via the activity log.
- All new logic covered by tests against `MockBackend`; `make ci` green; arch guard holds.
- **Out of scope (5C/M6):** `kill`/`delete`/`prune`/`export`, confirmation sheets for destructive
  ops, and the real embedded terminal / interactive exec.
