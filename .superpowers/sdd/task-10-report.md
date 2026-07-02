# Task 10 Report: Integration probe, docs, full verification

## Status: DONE

## What was implemented

### Step 1 — Integration test
Created `Tests/CapsuleIntegrationTests/ReleaseSourceIntegrationTests.swift` verbatim per
the brief: a `CAPSULE_INTEGRATION=1`-gated live probe of `GitHubReleaseClient.latestRelease()`
against the real apple/container GitHub releases API. Asserts the tag is non-empty, that a
`signedInstallerAsset` is present, and that its `downloadURL` is `https://`. Read-only — it
never calls `downloadPackage`.

Checked `Package.swift`: the `CapsuleIntegrationTests` target **already** depends on
`CapsuleRegistryClient` (added in an earlier task on this branch), so no dependency edit was
needed there.

### Step 2 — Docs
- `CLAUDE.md` (Module map): changed
  `` `CapsuleRegistryClient` (the `URLSession` Docker Hub search adapter) `` to
  `` `CapsuleRegistryClient` (the `URLSession` adapters: Docker Hub search + apple/container
  GitHub releases) ``, and reflowed the surrounding paragraph's line wraps to keep it tidy
  (content-only change otherwise).
- `README.md` (module responsibility table): changed the `CapsuleRegistryClient` row from
  "Unauthenticated Docker Hub search/tags over `URLSession`. Conforms to
  `ImageRegistrySearching`." to "`URLSession` adapters: unauthenticated Docker Hub search/tags
  (conforms to `ImageRegistrySearching`) + apple/container GitHub releases (conforms to
  `ContainerReleaseSource`)." — matching wording, naming both ports the module now conforms to.

No other content in either file was touched.

## Files changed
- `Tests/CapsuleIntegrationTests/ReleaseSourceIntegrationTests.swift` (new)
- `CLAUDE.md` (module map wording)
- `README.md` (module responsibility table wording)

## Full verification battery

1. `make format` — no changes produced (already formatted).
2. `make check` — swift-format lint (strict), `Scripts/check-architecture.sh`
   (`✅ Architecture boundaries OK`), `Scripts/check-headers.sh`
   (`✅ License headers OK`) — all green.
3. `make test` — `Executed 883 tests, with 12 tests skipped and 0 failures (0 unexpected)`
   (the 12 skips are the opt-in integration tests self-skipping, including the new one, since
   `CAPSULE_INTEGRATION` is unset for this run).
4. `make app` — **BUILD SUCCEEDED**.
5. Live probe: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CAPSULE_INTEGRATION=1
   swift test --filter ReleaseSourceIntegrationTests` (the explicit `DEVELOPER_DIR` is the
   known toolchain quirk from memory — `swift test` needs full Xcode's XCTest, not the CLT).
   Real output:

   ```
   Test Suite 'ReleaseSourceIntegrationTests' started at 2026-07-02 10:53:46.013.
   Test Case '-[CapsuleIntegrationTests.ReleaseSourceIntegrationTests testLatestReleaseCarriesSignedInstaller]' started.
   Test Case '-[CapsuleIntegrationTests.ReleaseSourceIntegrationTests testLatestReleaseCarriesSignedInstaller]' passed (0.442 seconds).
   Test Suite 'ReleaseSourceIntegrationTests' passed at 2026-07-02 10:53:46.455.
        Executed 1 test, with 0 failures (0 unexpected) in 0.442 (0.442) seconds
   ```

   The probe fetched the real latest apple/container release from `api.github.com`, confirmed
   a non-empty tag and a signed installer asset with an `https://` download URL. No rate
   limiting encountered.

## Commit
`046204a` — `test(integration)+docs: live release probe; RegistryClient charter covers GitHub releases`
(pre-commit hooks: swift-format lint + license headers, both passed).

## Concerns
None. This was the last task of the container-CLI-install/update feature; everything on the
branch (this commit plus the prior 5 commits from earlier tasks) is now verified end-to-end:
unit tests, architecture guard, license headers, real app build, and a live network probe
against the actual GitHub API all green. Per the autonomous-mode convention captured in
project memory, no push/PR was created — that decision is left to the user/finishing-a-branch
step.

## Final-review fixes

Three small fixes from final review, one commit.

### Fix 1 — disable "Update container…" while health is checking
`Sources/CapsuleUI/AboutDiagnosticsView.swift` gained a `let updateDisabled: Bool` parameter
(mirroring the existing `isRunning` pattern on `ServiceLogsView`), applied via
`.disabled(updateDisabled)` on the `about-update-container-button`. `SystemDetailView.swift`
already holds `let health: SystemHealth`; it now computes a private `updateDisabled` var
(`if case .checking = health { true } else { false }`) and passes it into
`AboutDiagnosticsView`. `SystemHealth` itself is never threaded into the About view — only
the derived Bool, per the design note in the brief. No test targets construct
`AboutDiagnosticsView` directly, so no other call sites needed updates.

### Fix 2 — https-only guard in the download path
`Sources/CapsuleRegistryClient/GitHubReleaseClient.swift`, `downloadPackage(_:to:)`: after the
existing "invalid URL" guard, added `guard url.scheme == "https" else { throw
ContainerReleaseError.network(message: "Refusing non-HTTPS download URL for \(asset.name).") }`
before any `session.bytes(for:)` call. New test
`GitHubReleaseClientTests.testDownloadPackageRefusesNonHTTPSURL` builds a
`ContainerCLIReleaseAsset` with an `http://` `downloadURL`, drains the stream, and asserts a
`ContainerReleaseError.network` is thrown — no fetcher seeding needed since the guard fires
before the network call.

### Fix 3 — guard against overlapping installs
`Sources/CapsuleDomain/ContainerCLIUpdateModel.swift`, `installLatest()`: now returns early
(calling `onActivity("An installer download is already running.")`) when
`taskCenter.activeTasks.contains { $0.kind == .cliInstall }` is already true, before starting
a second download task. New test
`ContainerCLIUpdateModelTests.testInstallLatestIgnoresOverlappingCalls` calls `installLatest()`
twice back-to-back and asserts `taskCenter.tasks.count == 1`, then awaits the single task to
completion.

### Verification
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter
  'ContainerCLIUpdateModelTests|GitHubReleaseClientTests'` — `Executed 14 tests, with 0
  failures (0 unexpected)`.
- `make format` — no changes produced (already formatted).
- `make check` — swift-format lint (strict), architecture guard, license headers — all green.
- `make test` — `Executed 885 tests, with 12 tests skipped and 0 failures (0 unexpected)`
  (883 prior + 2 new: the https-only-guard test and the overlapping-install-guard test).
- `make app` — **BUILD SUCCEEDED**.

### Commit
`fix(review): disable Update while checking; https-only downloads; single-install guard`
