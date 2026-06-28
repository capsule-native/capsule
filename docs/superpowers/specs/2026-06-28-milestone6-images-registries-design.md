# Milestone 6 · Images browser and registries — Design

Status: approved-to-build (autonomous; `/goal` directive). Date: 2026-06-28.
Branch: `milestone-6-images-registries`.

## 1. Goal & scope

Build the image-management surface and registry credential handling, mirroring the
container surface delivered in Milestone 5 (5A read / 5B+5C actions). Concretely:

- An **Images browser** from `container image list --format json` showing references
  (repo:tag), digests, and sizes, with search + sort + a dangling filter. The empty
  state must distinguish "no images" from "daemon failure" (same pattern as
  `ContainerBrowserModel.loadState`).
- An **Image inspector** with a friendly Summary tab and a Raw JSON tab, plus
  **digest-centric copy actions** (copy full digest, copy reference) to avoid ambiguity.
- **Image operations** as sheets/actions: `pull`, `push`, `save`, `load`, `tag`,
  `delete`/`rm` (single + bulk, surfacing dependency conflicts), `prune` (with a preview
  of what will be reclaimed).
- A **Registries** preferences pane backed by `registry login`/`logout`/`list`: a login
  sheet that **never echoes secrets**, a credential-test action, and confirmation before
  removing a login. Secrets are fed to the CLI via **`--password-stdin`** so they never
  appear on argv, in logs, in the activity feed, or in any task transcript.
- Long operations (`pull`/`push`/`save`/`load`) register **tasks** with state, a raw
  transcript, and retry. The Activity pane's Tasks/Progress tabs are placeholders today;
  M6 gives them a real, minimal backing model that Milestone 7 can expand.

Out of scope (YAGNI): saved scopes for images (containers have them; images get
search+sort+dangling-filter instead), Keychain integration beyond what the CLI already
does (apple/container stores its own credentials; we do not touch Keychain directly), and
per-layer/variant drill-down in the inspector (the Raw JSON tab covers it).

## 2. CLI facts (verified against `container` v1.0.0 `--help` on this machine)

```
image list   --format json|table|yaml|toml  [-q] [-v]
image inspect <images>...                    (JSON by default)
image pull   [--platform os/arch] [--progress auto|none|ansi|plain|color] <reference>
image push   [--platform os/arch] [--progress ...] <reference>
image save   [-o/--output <path>] [--platform os/arch] <references>...
image load   [-i/--input <path>] [--force]
image tag    <source> <target>
image prune  [--all]                         (default: dangling only; --all: all unused)
image delete [--all] [--force] <images>...   (--force = ignore not-found; NOT force-unref)
registry login  [--scheme ...] [--password-stdin] [-u/--username <u>] <server>
registry logout <registry>
registry list   [--format json] [-q]
```

Live `image list --format json` row shape (captured):

```json
{ "id": "28bd5fe8…(hex digest)",
  "configuration": {
    "name": "docker.io/library/alpine:latest",
    "creationDate": "2026-06-16T00:00:15Z",
    "descriptor": { "digest": "sha256:28bd5fe8…", "mediaType": "…index.v1+json", "size": 9218 } },
  "variants": [ … ] }
```

`registry list --format json` returns `[]` on a fresh machine. There is **no
`registry test`** subcommand: the credential-test action is implemented as a real
`registry login` attempt (the registry authenticates the credentials; success ⇒ valid).
We document this conflation honestly in the UI ("Test logs in to verify the credentials").

`image delete --force` only *ignores not-found errors*; it does **not** force-remove an
image that a container still references. So deleting a referenced image fails with a
dependency error on stderr — which we surface verbatim in the notice (acceptance:
"show dependency conflicts when images are still referenced").

## 3. Architecture & layering

Obeys the existing arch-guard rules (`ArchitectureGuardTests`):

- `CapsuleBackend` — extend the `ContainerBackend` port + value types. No deps.
- `CapsuleDomain` (imports `CapsuleBackend` only) — new `@Observable` models + value types.
- `CapsuleUI` (imports `CapsuleDomain` only) — new SwiftUI views/sheets. No backend types
  in any UI signature.
- `CapsuleCLIBackend` (imports `CapsuleBackend`, `CapsuleDiagnostics`) — CLI adapter.
- `CapsuleApp` — composition root wires everything, adds the Settings scene.

### 3.1 Backend port additions (`ContainerBackend`)

```swift
// Images (existing: listImages, inspectImage, removeImage, pullImage)
func pushImage(reference: String, platform: String?) -> AsyncThrowingStream<OutputLine, Error>
func saveImage(references: [String], to url: URL, platform: String?) async throws
func loadImage(from url: URL) async throws
func tagImage(source: String, target: String) async throws
func pruneImages(all: Bool) async throws -> PruneResult
// pullImage gains a platform overload (keep the no-arg one via default-arg extension)
func pullImage(reference: String, platform: String?) -> AsyncThrowingStream<OutputLine, Error>

// Registries (existing: listRegistries)
func registryLogin(server: String, username: String?, password: String?) async throws
func registryLogout(server: String) async throws
func registryTest(server: String, username: String?, password: String?) async throws
```

`registryLogin`/`registryTest` pass `--password-stdin` and write the password to the
child's stdin (new `CLIProcessRunner.run(_:environment:standardInput:)`). The password is
**never** placed in `arguments`, so it cannot leak through `commandDescription`, the
`Log.backend.debug` argv line, the error's `command:` field, or any transcript.

### 3.2 Value-type enrichment (`CapsuleBackend`)

`ImageSummary` gains `digest: String` (full `sha256:…` from `descriptor.digest`) and
`createdAt: String?` (the raw ISO string). `OutputParser.parseImages` populates them from
`CLIImageRecord` (already decodes `descriptor.digest` + `creationDate`). Defaulted inits
keep existing callers/tests compiling.

`RegistrySummary` stays minimal (`server`). apple/container exposes no auth-state or
last-used metadata locally, so we do not invent it; the pane shows the server list the CLI
reports. (Documented; "surfaced where available locally" = nothing extra is available.)

### 3.3 Domain models (`CapsuleDomain`)

- **`Image`** (existing, enriched): add `repository`, `tag`, `digest`, `shortDigest`
  (12 hex chars after `sha256:`), `createdAt: Date?`, `isDangling` (tag/ref is `<none>`).
  `init(summary:)` parses `reference` into repo/tag.
- **`ImageBrowserModel`** (new, mirrors `ContainerBrowserModel`): `allImages`,
  `loadState: ImageLoadState` (`idle/loading/loaded/unavailable(ErrorDetail)`),
  `searchText`, `sort: ImageSort` (name/size/created), `showDanglingOnly`, `selection`,
  derived `rows`, `isEmptyButHealthy`, `noMatches`, `refresh()`, `inspect(reference:)
  -> ImageInspection`.
- **`ImageActionsModel`** (new, mirrors `ContainerLifecycleModel` for non-streaming ops):
  `busy`, `notice: LifecycleNotice?`, `confirmation: ConfirmationRequest?`; methods
  `tag(source:target:)`, `delete(reference:)`/`deleteAll`, `computePruneTargets()`,
  `prune(all:)`. Streaming ops (pull/push/save/load) go through the task center (below).
- **`TaskCenter`** (new, `@Observable`) + **`OperationTask`** value/observable: the real
  backing for the Activity pane's Tasks/Progress tabs. `OperationTask` holds `id`,
  `title`, `kind` (pull/push/save/load), `state: TaskState`, `transcript: [OutputLine]`,
  and a `retry: () -> Void` closure. `TaskCenter` exposes `tasks`, `start(...)`,
  `append(line:to:)`, `finish(_:state:)`, `retry(_:)`, and `activeProgressTasks`.
  - pull/push stream `OutputLine`s → appended to the transcript; state is
    `.running(progress: nil)` (indeterminate — `--progress plain` emits lines, not a clean
    %), flipping to `.succeeded`/`.failed(DiagnosticInfo)` on stream end/throw.
  - save/load are non-streaming → `.running(progress: nil)` then succeeded/failed; their
    transcript captures the normalized error on failure.

`ConfirmationKind` gains `.deleteImage(force:)` and `.pruneImages(all:)`; `push` gets its
own confirmation factory (`ConfirmationRequest.pushImage(reference:destination:)`) so a
push always confirms its destination repo (acceptance: "confirm destination repo").

### 3.4 UI (`CapsuleUI`)

- **Routing**: `ContentColumnView.runningContent` adds `case .images → ImageListView(...)`.
  `AppShellView` inspector adds `if selection == .images → ImageInspectorView(...)`.
- **`ImageListView`** (mirrors `ContainerListView`): `Table` of rows (status dot for
  dangling, Reference, Tag, Digest (short, monospaced), Size, Created relative), a
  searchable field, a sort Picker + a "Dangling only" toggle in the toolbar, a Pull button,
  a Clean Up (prune) button, a context menu (Push…, Save…, Tag…, Copy Digest, Copy
  Reference, Delete…), bulk delete via `onDeleteCommand`. Sheets via one
  `ImageSheet` enum (`pull`, `push`, `save` handled by NSSavePanel, `load`, `tag`,
  `confirm`, `prune`).
- **Sheets**: `PullImageSheet` (reference paste field + platform field + a live transcript
  area fed by the task), `PushImageSheet` (reference + destination confirm), `TagImageSheet`
  (source shown read-only with its digest + a target field), `LoadImageSheet` (file picker +
  drag/drop with archive-type validation: `.tar`/`.tar.gz`/OCI dir), `ImagePruneSheet`
  (preview of dangling [or all-unused] candidates + reclaimed result), reuse
  `ConfirmationSheet` for delete/push/prune confirmations. Save uses `NSSavePanel`
  (`.tar`), like container export.
- **`ImageInspectorView`** (mirrors `ContainerInspectorView`): Summary (repository, tag,
  full digest with a copy button, size, created) + Raw JSON tab (copyable). Digest-centric
  copy actions live here and in the list context menu.
- **Activity pane**: replace the Tasks/Progress placeholders with real lists bound to
  `TaskCenter`: Tasks shows each `OperationTask` with a state glyph, a disclosure for its
  transcript, and a Retry button on failure; Progress shows active transfers with a
  progress view (indeterminate) + inline transcript tail.
- **Registries preferences**: a new `Settings` scene → `PreferencesView` with a Registries
  pane. `RegistriesView` lists logins (server), a "+" presents `RegistryLoginSheet`
  (server, username, `SecureField` password — never rendered/echoed, a Test button, a Log
  In button; raw transcript shown on auth failure), and a "−"/remove that confirms via
  `ConfirmationSheet` before `registry logout`.

### 3.5 Composition (`CapsuleApp`)

`AppEnvironment` gains `imageBrowserModel`, `imageActionsModel`, `taskCenter`,
`registriesModel`; `live()` wires them to the CLI backend with `ErrorNormalizer.normalize`
and `shell.appendActivity`. Pull/push/save/load actions are created so the UI fires them
without naming backend types; they register an `OperationTask` and stream into it.
`CapsuleScene` adds a `Settings { PreferencesView(registriesModel:) }` scene;
`CapsuleCommands` adds nothing new (the standard Settings menu item opens it; ⌘,).

## 4. Error handling

- All backend failures normalize through `ErrorNormalizer.normalize` → `CapsuleError` →
  `ErrorDetail`, exactly as containers do. Raw transcripts (stdout+stderr) stay visible:
  pull/push/save/load keep their full transcript in the task; registry login shows the raw
  failure in the sheet; delete surfaces the raw dependency-conflict stderr in the notice.
- Benign cases: `image delete` of an already-absent image with `--force` is idempotent
  (mirror `isBenignAlreadyRemoved`). Tag/login/logout surface failures directly.
- Secret safety is an invariant, asserted by tests: the argv built for login/test never
  contains the password; the transcript/diagnostic of a failed login never contains it.

## 5. Testing (all against `MockBackend`)

New `MockBackend` support: seeded images carry digest/createdAt; new methods mutate state
and record last-call params (`lastTaggedSource/Target`, `lastSavedURL`, `lastLoadedURL`,
`lastLogin: (server,username,password)`, `lastLogout`, `prunedAll`), with `failure`
injection. Streaming push/save/load reuse the seeded-stream pattern.

Unit tests (mirroring existing suites):
- `ImageTests` — reference→repo/tag/digest/dangling parsing; summary mapping.
- `ImageBrowserModelTests` — load/empty-vs-unavailable, search, sort, dangling filter,
  selection intersection, inspect.
- `ImageActionsModelTests` — tag, delete (incl. idempotent not-found + dependency-conflict
  notice), bulk delete, prune targets + result.
- `TaskCenterTests` — start/append/finish, failed→retry re-runs, progress-active set.
- `RegistriesModelTests` — list, login (calls backend with right server/user; password via
  the password arg, not argv), logout, test; **secret-never-in-argv** assertion via a new
  `CLICommandTests` case (`registryLogin` argv excludes the password, includes
  `--password-stdin`).
- `CLICommandTests` — argv for every new command (push/save/load/tag/prune/delete-all,
  registry login/logout) matches the verified `--help` flags.
- `OutputParserTests` — `parseImages` populates digest + createdAt from the real captured
  JSON; lenient on drift.
- `ConfirmationTests` — image delete (single/bulk/force), prune(all), push-destination.
- `ArchitectureGuardTests` — unchanged rules keep passing (no new violations).
- `CompositionTests`/`AppEnvironmentActionsTests` — env exposes the new models; a pull
  action registers a task and streams into it.

Acceptance maps 1:1 to the goal: list with tags/digests ✓; pull/push/save/load/tag/delete/
prune with correct prompts + visible raw transcripts on failure ✓; registry
login/logout/list without printing secrets + a test action ✓; pushes confirm destination ✓;
all tested against `MockBackend` ✓.

## 6. Decisions log (autonomous; documented for async review)

1. **No saved scopes for images** — search + sort + dangling-filter instead (YAGNI).
2. **No Keychain code** — apple/container owns credential storage; we drive its CLI only.
3. **`registry test` = a real `registry login`** (no dry-run verb exists); labelled honestly.
4. **Progress is indeterminate** for pull/push (the CLI's plain progress isn't a clean %);
   the transcript is the source of truth. Milestone 7 can parse finer progress.
5. **Secrets via `--password-stdin`**, never argv — enforced by a unit test.
6. **One milestone, one branch**, phased commits (not split into 6A/6B/6C).
</content>
</invoke>
