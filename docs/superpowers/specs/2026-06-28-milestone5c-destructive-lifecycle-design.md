# Milestone 5C · Container lifecycle — destructive (kill / delete / prune / export) — Design

_Phase 2 · Core workflows. Date: 2026-06-28. Branch: `milestone-5c-destructive`._

## Background

Milestone 5 was decomposed into 5A (browser+inspector, merged), 5B (non-destructive
lifecycle: start/stop/stats, merged), **5C (this — destructive lifecycle)**, and M6 (embedded
terminal, libghostty). 5C adds the destructive actions with the safety patterns the goal
requires, building on 5B's `ContainerLifecycleModel`, the confirmation infrastructure, and the
existing `removeContainer(id:force:)` port method. The design here was adversarially critiqued
in the Milestone-5 design workflow; its must-fixes are folded in.

## Scope (5C)

- **kill / Force Stop** — a destructive contextual-menu action; `killContainer(id:signal:)`
  (default signal KILL). Confirmation sheet when **more than one** container is targeted.
  Becomes the real escalation target for 5B's stop-hang notice (single hung container → kill
  without a separate confirmation, since the user already asked to stop).
- **delete / rm** — single and bulk; reuses `removeContainer(id:force:)`. macOS `Table` has no
  swipe actions, so "single delete" is a context-menu / ⌫-key / toolbar affordance (the
  spec's "swipe-style" intent, adapted to AppKit reality). Always confirmed for bulk and for
  any running container; the sheet **explains dependencies** and **recommends Stop first
  unless `--force`** (a "Force delete (running)" toggle in the sheet).
- **prune** — a **Cleanup sheet** that **precomputes the affected set** (the stopped
  containers) by listing `--all` and filtering, showing **count + names**. A freed-space
  *estimate* is **infeasible** (the CLI exposes no per-container size in list/inspect, and
  `prune` emits no per-item breakdown), so the sheet is honest: it shows the count/names
  before, and the **actual reclaimed string** after (`PruneResult.reclaimedDescription`).
- **export** — `exportContainer(id:to:URL)` via an `NSSavePanel`; **validate the
  stopped-state prerequisite** before launching (a caution if the container is running);
  `--output` keeps the tar off stdout. Long-running and non-cancellable for now (a spinner).

Every destructive op routes failures through the normalized error model and offers the
retry-in-terminal (clipboard) interim. The embedded terminal stays M6.

## Verified CLI facts (container v1.0.0)

- `kill [--all] [-s/--signal <sig> default KILL] [<ids>…]`
- `delete/rm [--all] [-f/--force] [<ids>…]`
- `prune` — no flags, no dry-run, no JSON; prints a human "Reclaimed … in disk space" line
  (locale-formatted; empty case "Reclaimed Zero KB in disk space"); exit 0 on success. The
  reclaimed line's stream (stdout vs stderr) is **unverified** → the parser reads **both**.
- `export [-o/--output <path>] <id>` — single id; exits 1 on failure.
- `list --format json` has **no per-container disk size** (freed-space estimate impossible).
- Destructive ops on a missing/stopped container exit 1 with stderr
  `Error: internalError: "failed to …" (cause: "notFound: …")` / "not running".

## Architecture & layering (unchanged)

UI → Domain → Backend port; adapter `CapsuleCLIBackend`; root `CapsuleApp`. Arch guard:
UI imports no Backend module (no Backend type in a UI signature); Domain imports no UI and no
`Foundation.Process`. New Backend value types are Foundation-only and mapped into domain types.

## Backend port expansion (5C)

New value type in `CapsuleBackend` (`BackendLifecycleTypes.swift`):

- `PruneResult { reclaimedDescription: String?; raw: String }` — `raw` holds **stdout AND
  stderr** combined; `reclaimedDescription` is the parsed "Reclaimed …" line if present.

Port methods (`ContainerBackend`):

- `killContainer(id:signal:)` — `signal: String?` (nil ⇒ CLI default KILL).
- `pruneContainers() -> PruneResult`.
- `exportContainer(id:to:URL)`.

Adapter (`CapsuleCLIBackend`):

- `CLICommand.killContainer(id:signal:)` → `["kill"] + (-s signal?) + [id]`;
  `CLICommand.pruneContainers()` → `["prune"]`;
  `CLICommand.exportContainer(id:to:)` → `["export","--output",<path>,id]`.
- `pruneContainers()` runs prune (not `runChecked`'s stderr-as-failure path if exit 0) and
  builds `PruneResult` from stdout+stderr via `OutputParser.parsePruneResult` (best-effort
  regex/substring for "Reclaimed … in disk space").
- `exportContainer` uses `runChecked` (export exits 1 on failure).

`MockBackend`: implement all three; `pruneContainers` removes stopped containers and returns a
`PruneResult(reclaimedDescription: "Reclaimed N items", raw:)`; record `lastKillSignal`,
`lastExportURL`; honor `failure`.

## Domain design (5C)

- `ConfirmationRequest` (new, in `Lifecycle.swift` or a new `Confirmation.swift`): a pure,
  `Equatable`/`Sendable` value type describing a destructive confirmation —
  `{ title, message, confirmTitle, isDestructive: Bool, targetIDs: [String], kind:
  ConfirmationKind }`, where `ConfirmationKind ∈ { kill, delete(force: Bool), exportNotStopped }`.
  It is **data**, so it is testable and the UI renders it via one generic sheet.
- `ContainerLifecycleModel` gains:
  - `kill(id:signal:) async -> StopOutcome` and `killAll(ids:)` (bulk, domain loop, per-id
    attribution). The 5B hang notice's Force Stop is **re-routed to `kill`** (the real
    destructive escalation) for a single hung container.
  - `delete(id:force:) async` and `deleteAll(ids:force:)` (bulk, domain loop). Uses the
    existing `removeContainer(id:force:)`.
  - `prune() async -> PruneResult` — calls the backend, refreshes the list, surfaces the
    reclaimed description in the activity log.
  - `computePruneTargets() async -> [Container]` — lists `--all`, filters stopped, for the
    Cleanup sheet precompute.
  - `export(id:to:URL) async` — validates stopped-state first (returns a caution path when
    running), then calls the backend.
  - A published `confirmation: ConfirmationRequest?` the UI binds to; helper builders
    `confirmKill(ids:)`, `confirmDelete(ids:running:)`, etc., that decide **when** a sheet is
    required (always for delete of running/bulk; for kill when `ids.count > 1`).
  - "already stopped / not running" benign handling extended to kill/delete (reusing the 5B
    interception so it isn't misread as a daemon outage).

All destructive model methods route failures through `normalize → ErrorDetail → notice` and
offer retry-in-terminal (clipboard interim).

## UI design (5C)

- `ConfirmationSheet` (new): renders a `ConfirmationRequest` — title, message (incl. the
  "stop first / dependency" guidance for delete), a destructive confirm button, an optional
  "Force (running)" toggle for delete, Cancel.
- `PruneSheet` (new / Cleanup sheet): on appear, calls `computePruneTargets()`; shows the
  count + names that will be removed and the honest "freed space can't be estimated" note;
  Cleanup button runs `prune()` and shows the reclaimed result; empty-state when nothing to
  prune.
- `ContainerListView`: a **destructive** section in the context menu + toolbar — Force Stop
  (kill), Delete, and a "Clean Up…" entry opening the Prune sheet; Export… opening the save
  panel. Destructive items use `role: .destructive`. Present `ConfirmationSheet`/`PruneSheet`
  via `sheet(item:)`.
- Export uses `NSSavePanel` (AppKit, permitted in UI) defaulting to `<name>.tar`; on a running
  container, route through the export-not-stopped confirmation first.
- `LifecycleNoticeView` / hang notice: the Force Stop button now triggers the real `kill`
  (single hung container, no extra sheet).

## Safety / messaging (5C)

- **Confirmation always** for: bulk kill (`>1`), any delete of a running container, bulk
  delete, and export of a running container. Single kill of one explicitly-targeted (or hung)
  container proceeds without a redundant sheet (the action itself is the intent), matching the
  goal's "confirm when multiple are targeted".
- Delete messaging recommends **Stop first** and explains that a running container needs
  `--force`; the sheet's Force toggle makes that explicit.
- Prune sheet shows the **precomputed affected set** and is honest that a byte-level freed
  estimate is unavailable; it reports the actual reclaimed string post-run.
- Export validates stopped-state and warns before exporting a running container.
- Success → activity-log line; failures → `ErrorDetail` notice + retry-in-terminal (clipboard).

## Testing (TDD, against `MockBackend`)

- **Backend/CLI:** `CLICommand` kill/prune/export argv; `OutputParser.parsePruneResult`
  (reclaimed line on stdout, on stderr, and absent); `MockBackend` kill/prune/export behavior
  (prune removes stopped, records signal/URL).
- **Domain:** `ConfirmationRequest` builders (when a sheet is required vs not: single vs bulk
  kill, running vs stopped delete, export running); kill/delete/prune/export model methods incl.
  benign "already stopped" on kill/delete; `computePruneTargets` filters stopped; export
  stopped-state validation; the hang notice Force Stop now issues `kill`.
- **UI:** logic lives in the model (headless-tested); views verified by build + inspection.
  Arch guard + `make ci` green.

## Acceptance (5C)

- `kill`/Force Stop works from a destructive contextual menu, confirming when multiple are
  targeted; the 5B hang escalation now performs the real kill.
- `delete`/`rm` works single + bulk, always confirming destructive/bulk/running deletes, with
  dependency guidance and a Force option.
- `prune` opens a Cleanup sheet that precomputes the affected containers (count + names),
  is honest about the freed-space estimate, and reports the actual reclaimed result.
- `export` opens a save panel, validates the stopped-state prerequisite, and writes the tar.
- All destructive failures route through the normalized error model with a retry-in-terminal
  (clipboard) path; bulk/destructive ops always present a confirmation sheet.
- Tested against `MockBackend`; `make ci` green; arch guard holds.
- **Out of scope (M6):** the real embedded terminal / interactive exec.
