# Milestone 6 · Images browser and registries — Implementation plan

Design: `docs/superpowers/specs/2026-06-28-milestone6-images-registries-design.md`.
Method: TDD (red → green → refactor), one phase per logical layer, commit per phase.
All behaviour tested against `MockBackend`. Build/test command: `swift test` (SwiftPM).

## Phase 0 — Backend port + value types
1. (red) `CLICommandTests`: argv for `pushImage`, `saveImage`, `loadImage`, `tagImage`,
   `pruneImages(all:)`, `removeImage(all:force:)`, `pullImage(platform:)`,
   `registryLogin(server:username:)` (asserts `--password-stdin`, **no password in argv**),
   `registryLogout`. `OutputParserTests`: `parseImages` populates `digest`+`createdAt`.
2. (green) Enrich `ImageSummary` (`digest`, `createdAt`). Add `CLICommand` factories.
   Add `CLIProcessRunner.run(_:environment:standardInput:)`. Implement new methods in
   `CLIContainerBackend`. Add port methods to `ContainerBackend` (+ default-arg
   convenience extensions). Implement in `MockBackend` with last-call tracking + seeded
   digest/createdAt.
3. (green) `MockBackendTests`: new methods mutate/record; `failure` injection.

## Phase 1 — Images read surface
1. (red) `ImageTests` (reference→repo/tag/digest/dangling/shortDigest, summary map),
   `ImageBrowserModelTests` (loaded vs unavailable vs empty-but-healthy vs no-matches;
   search; sort name/size/created; dangling filter; selection intersection; inspect).
2. (green) Enrich `Image`; add `ImageBrowserModel`, `ImageSort`, `ImageInspection`,
   `ImageLoadState`.
3. (green, UI) `ImageListView` (Table + searchable + sort/dangling toolbar + context menu
   with Copy Digest/Reference), `ImageInspectorView` (Summary + Raw JSON + digest copy);
   route `.images` in `ContentColumnView` + `AppShellView`. Wire models through
   `AppEnvironment`/`CapsuleScene`/`RootView`.

## Phase 2 — Image operations
1. (red) `ImageActionsModelTests` (tag; delete single/bulk; idempotent not-found;
   dependency-conflict → notice with raw stderr; prune targets + result),
   `ConfirmationTests` (image delete single/bulk/force, prune all, push destination).
2. (green) `ImageActionsModel`; extend `ConfirmationKind` (`.deleteImage(force:)`,
   `.pruneImages(all:)`) + `ConfirmationRequest` factories incl. `pushImage`.
3. (green, UI) `TagImageSheet`, `ImagePruneSheet`, delete/prune via `ConfirmationSheet`;
   wire into `ImageListView` context menu + toolbar.

## Phase 3 — Long operations as tasks
1. (red) `TaskCenterTests` (start/append/finish; failed→retry re-runs; active-progress set).
2. (green) `OperationTask` + `TaskCenter`; pull/push stream into transcript, save/load
   non-stream; expose start closures from `AppEnvironment`.
3. (green, UI) Replace Activity pane Tasks/Progress placeholders with real lists (state
   glyph, transcript disclosure, Retry). `PullImageSheet`, `PushImageSheet` (confirm
   destination), `LoadImageSheet` (file picker + drag/drop + archive-type validation),
   Save via `NSSavePanel`. Wire into `ImageListView`.

## Phase 4 — Registries preferences
1. (red) `RegistriesModelTests` (list/login/logout/test; backend called with right
   server/username; password passed via the password parameter; failure → notice;
   logout confirmation policy). Secret-never-in-argv already covered in Phase 0
   `CLICommandTests`.
2. (green) `RegistriesModel`.
3. (green, UI) `Settings` scene + `PreferencesView` + `RegistriesView` +
   `RegistryLoginSheet` (`SecureField`, Test, raw transcript on failure, remove confirm).
   Wire `registriesModel` through `AppEnvironment` + `CapsuleScene`.

## Phase 5 — Verify, review, finish
1. `swift build` + `swift test` green; `ArchitectureGuardTests` parity; swift-format.
2. Adversarial code-review subagent; address findings (re-verify after each fix).
3. Interactive GUI smoke if feasible (mock-backed previews / live app).
4. Per-phase commits already landed; open PR per `finishing-a-development-branch`.
</content>
