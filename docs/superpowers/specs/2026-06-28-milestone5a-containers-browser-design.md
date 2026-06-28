# Milestone 5A · Containers browser + inspector — Design

_Phase 2 · Core workflows. Date: 2026-06-28._

## Background

Milestone 5 ("Containers browser, inspector, and lifecycle") is the primary daily
surface of Capsule. It is large enough to warrant decomposition, so it is split into
two independent spec → plan → implement cycles:

- **5A (this document):** the **read surface** — a live containers browser (list,
  search, filters, persisted saved scopes, multi-select, keyboard-navigable rows) and a
  trailing **inspector** with a friendly summary and a raw-JSON tab. Ships and merges on
  its own.
- **5B (separate cycle):** the **write surface** — the seven lifecycle actions
  (`start`, `stop`, `kill`/Force Stop, `delete`/`rm`, `prune`, `stats`, `export`) with
  their confirmation/escalation/safety patterns, hung off 5A's selection set.

This split was chosen so the browser can be proven correct before destructive operations
are layered on top.

## Goal (5A)

A live, `Table`-based containers browser in the content column, backed by
`container list --all --format json` (through the existing `listContainers(all:)` port;
`MockBackend` for tests), with:

- text search, state/column filters, multi-select, keyboard-navigable rows;
- persisted **saved scopes** — built-in *All / Running / Stopped* plus user-saved named
  filters;
- a trailing **inspector** with a **Summary** tab (friendly fields) and a **Raw JSON**
  tab (from `container inspect`, pretty-printed, copy-to-clipboard), which still renders
  the raw payload when decoding drifts across CLI versions;
- daemon-down continues to show the **health state, not an empty list** (reusing
  Milestone 4's gating).

### Out of scope (deferred to 5B)

Every lifecycle action — `start`, `stop`, `kill`, `delete`, `prune`, `stats`, `export`
— and their confirmation sheets, hang-escalation, and freed-space preview. 5A builds the
`Table` and selection model so 5B can attach toolbar/context-menu commands without
rework, but adds **no** mutating port methods.

## Architecture — where browser state lives

**Decision: a dedicated domain model (Approach A).**

A new `@Observable @MainActor ContainerBrowserModel` in `CapsuleDomain` owns:

- the container list and its load state,
- `searchText`,
- the active `ContainerScope`,
- `selection: Set<Container.ID>`,
- derived, filtered, sorted rows (a computed property),
- the set of saved scopes.

Saved scopes persist through an **injected `ScopeStore`** protocol: a
UserDefaults-backed implementation is supplied by the composition root; an in-memory
double is used in tests. This mirrors how Milestone 4 injected the error `normalize`
closure to keep `CapsuleDomain` free of `CapsuleDiagnostics` and of UI — the domain
stays UI-free and fully unit-testable.

### Rejected alternatives

- **Approach B — extend `WorkspaceModel`.** It already owns images + load state; adding
  search/scope/selection turns it into a god-object that mixes concerns and is harder to
  test in isolation. Rejected for violating "one clear purpose".
- **Approach C — keep query/selection in SwiftUI `@State`/`ShellState`.** Filtering and
  scope logic would become untestable without a UI-inspection harness, and 5B's
  domain-level lifecycle actions could not see the selection. Rejected.

`WorkspaceModel` is left as-is; `ContainerBrowserModel` is the containers surface's owner.
Purely-visual concerns (which pane is open) remain in `ShellState`.

## Data model touch-ups (bounded)

`ContainerSummary` (backend port value type) and the domain `Container` gain a single
field: **`createdAt`**. The real `container list --format json` payload already carries
it as `configuration.creationDate` (an ISO-8601 string), so this is a mapping change, not
a new query.

- `ContainerSummary.createdAt: String?` — the raw ISO-8601 string from the wire.
- `Container.createdAt: Date?` — parsed in the domain for a *Created* column (relative
  formatting) and the friendly summary.

No other wire changes. `id`, `name`, `image`, `state`, `ip` already exist and cover the
remaining columns/fields.

## Components

### Backend / CLI (`CapsuleBackend`, `CapsuleCLIBackend`)

- No new port methods: `listContainers(all:)` and
  `inspectContainer(id:) -> Parsed<ContainerSummary>` already exist, and `Parsed`
  already retains the raw payload — exactly what the Raw JSON tab needs.
- `OutputParser` / `WireModels`: map `configuration.creationDate` into
  `ContainerSummary.createdAt`.
- `MockBackend.sampleContainers`: enrich with `createdAt` and a third row so the browser,
  filters, and multi-select have realistic data in previews and tests.

### Domain (`CapsuleDomain`)

- `Container` — gains `createdAt: Date?`; mapping from `ContainerSummary` parses the ISO
  string (lenient: unparseable → `nil`).
- `ContainerScope` — a `Sendable`, `Codable`, `Identifiable` named filter: a `name`, a
  `StateFilter` (`all` / `running` / `stopped` / `created`), and an optional text term.
  Built-in scopes (*All*, *Running*, *Stopped*) are static constants; user scopes are
  saved copies. A scope exposes `matches(_:Container) -> Bool` and combines with the live
  `searchText`.
- `ScopeStore` — protocol `{ func load() -> [ContainerScope]; func save([ContainerScope]) }`.
  An in-memory conformance lives in the test target; the UserDefaults-backed conformance
  is provided by the composition root (`CapsuleApp`), keeping `CapsuleDomain` free of any
  persistence-key knowledge it should not own. (Foundation/`UserDefaults` is permitted in
  the domain, but injection keeps it testable and the keys in one place.)
- `ContainerBrowserModel` — `@Observable @MainActor`:
  - `refresh()` — loads via `backend.listContainers(all: true)`, maps to `Container`,
    sets `loadState`. On throw, routes through the injected `normalize` closure to an
    `ErrorDetail`; **never** presents a false-empty list.
  - `rows` — computed: containers filtered by the active scope **and** `searchText`
    (matched across name / id / image), sorted (default by name).
  - `selection: Set<Container.ID>`, plus a `selectedContainers` convenience.
  - `inspect(id:) async -> Parsed<ContainerSummary>` (or a small `ContainerInspection`
    value) feeding the inspector's Raw JSON tab.
  - saved-scope management: `addScope`, `removeScope`, `activate`, persisted via
    `ScopeStore`.
  - distinguishes three list states: **unavailable** (daemon down → health, not empty),
    **emptyButHealthy** (zero containers, service up → friendly empty state),
    **loaded(rows)**.

### UI (`CapsuleUI`)

- `ContainerListView` — a macOS `Table` bound to `ContainerBrowserModel`:
  - columns: State (colored indicator via `CapsuleColors`), Name, Image, IP, Created;
  - `selection: Set<Container.ID>` for multi-select; rows keyboard-navigable (native);
  - `.searchable` bound to `searchText`;
  - a scope picker in the toolbar listing built-in + saved scopes, with a
    "Save current as scope…" affordance (small sheet/prompt for a name);
  - column sorting via `Table`'s `sortOrder`.
- `ContainerInspectorView` — a `TabView`:
  - **Summary** — `LabeledContent` rows (Name, short ID, Image, State, IP, Created); a
    friendly multi-select summary ("3 containers selected") when `selection.count > 1`;
    an empty prompt when nothing is selected.
  - **Raw JSON** — monospaced, scrollable text of the pretty-printed `inspect` payload,
    with a **Copy** button (`NSPasteboard`, AppKit is permitted in the UI layer). Falls
    back to the unmodified raw string when it is not valid JSON or decoding drifts.
- `ContentColumnView` — routes `.containers` + `health.isRunning` →
  `ContainerListView`; non-running keeps the existing health/error gating. The existing
  `.inspector` slot renders `ContainerInspectorView` for the current selection.

## Error & empty states

- Load failures route through the injected normalizer → `ErrorDetail` (the same path as
  `SystemStatusModel`), surfaced as a `ContentUnavailableView` with recovery actions —
  never a silent empty table.
- **Genuinely empty but healthy** (zero containers, service up) shows a distinct,
  friendly "No containers yet" empty state, kept separate from daemon-down.
- Daemon-down is unchanged: `ContentColumnView`'s health gate already shows the health
  state with recovery actions when the service is not running.

## Testing (TDD, against `MockBackend`)

- **Domain:**
  - filtering + search + scope application produce the expected `rows`;
  - selection behavior (`selectedContainers`, clearing on refresh as appropriate);
  - daemon-down resolves to the unavailable state, **not** empty;
  - load error routes through the injected normalizer to an `ErrorDetail`;
  - `ScopeStore` round-trip (save → load) and add/remove scope;
  - `Container` mapping incl. `createdAt` (valid ISO parses; garbage → `nil`).
- **CLI:** `OutputParser` extracts `createdAt`; raw payload is preserved when the typed
  decode fails (`Parsed.value == nil`, `raw` intact).
- **UI:** filtering/scope logic lives in the model and is verified headless. Views are
  verified by build + inspection, consistent with Milestone 4. The architecture guard and
  `make ci` (build zero-warning, `swift-format --strict`, arch, headers, unit +
  integration) stay green.

## Constraints discovered in the real CLI (noted for 5B)

These do not affect 5A but are recorded now:

- `container prune` has **no dry-run and no JSON output** ("Remove all stopped
  containers" only). 5B's "freed-space estimate" must be computed client-side by
  enumerating stopped containers.
- `container list --format json` exposes **no per-container disk size**, so that 5B
  estimate will be best-effort/approximate (or surfaced as "N containers will be
  removed" when size is unavailable).

## Acceptance (5A)

- Containers list live from real `container list --format json` (and from `MockBackend`
  in tests), with working **search, state/column filters, persisted saved scopes, and
  multi-select**; rows keyboard-navigable.
- Inspector shows a **friendly Summary** and a **Raw JSON** tab populated from
  `container inspect`, with copy-to-clipboard and raw-payload fallback on decode drift.
- **Daemon-down shows the health state, not empty**; zero-containers-but-healthy shows a
  distinct friendly empty state.
- All new logic is covered by tests against `MockBackend`; `make ci` is green and the
  architecture guard holds (UI imports no Backend; Domain imports no UI and no `Process`).
