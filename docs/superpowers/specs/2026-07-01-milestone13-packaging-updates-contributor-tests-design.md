# Milestone 13 — Packaging, updates, contributor infra & tests (design)

_Date: 2026-07-01 · Branch: `milestone-13-packaging-updates-contributor-tests`_

## Goal

Turn Capsule into a distributable, scriptable, open-source project:

1. **Distribution** — Developer ID signing + notarization + stapling with Hardened Runtime as
   the default (and only) v1 path. Mac App Store is explicitly out of scope (sandbox/XPC
   mismatch with the installed, unsandboxed `container` service).
2. **Auto-updates** — Sparkle via SwiftPM for the unsandboxed build, with a lightweight
   in-app updater surface (Check for Updates… menu + a Preferences “Updates” section).
3. **Privacy** — an in-app Privacy page stating exactly what is collected (local-only logging,
   opt-in crash submission) and what is never collected (secrets, command content unless
   explicitly approved). `NSLocalNetworkUsageDescription` stays populated.
4. **Contributor contract** — an expanded `CONTRIBUTING.md` (architecture map, code-style
   rules, screenshot policy), `CODEOWNERS` (UI shell / backend adapter / automation / release
   pipeline), and issue + PR templates. The bug template always captures Capsule version,
   `container system version`, host macOS version, and an exported diagnostic bundle.
5. **Tests** — unit tests (domain / argument building / output parsing against `MockBackend`,
   no real process), small golden UI tests for critical flows, integration tests gated to
   Apple-silicon runners, and coverage reporting wired into the build + CI.

## Scope boundaries & what is verifiable here

The two acceptance items that require secrets/hosting we cannot fully *execute* in this
environment are built as complete, correct, dry-runnable machinery and flagged honestly:

- **A real signed/notarized/stapled artifact** needs a Developer ID identity + notary
  credentials. We ship the full pipeline (scripts + Makefile targets + GitHub Actions
  release workflow) with a `--dry-run` mode that prints the exact command plan, and it fails
  with a clear message when credentials are absent. Verifiable: dry-run output, script
  correctness, `shellcheck`-clean.
- **A real end-to-end Sparkle update** needs a hosted appcast + two signed builds. We ship the
  full integration (dependency, `UpdaterDriving` seam, Sparkle-backed driver, menu +
  Preferences UI, Info.plist feed keys, appcast generation script) and unit-test the seam.
  Verifiable: it compiles + links, `make app` produces a bundle that hosts the updater, unit
  tests cover the model/driver contract.

Everything else — contributor infra, privacy page, unit tests, coverage, golden UI tests
compiling, re-enabled CI — is fully verifiable and must pass before the milestone is claimed.

## Design decisions

### D1 — Sparkle seam: `UpdaterDriving` in CapsuleUI, `SparkleUpdaterDriver` in CapsuleApp
Only the composition root (`CapsuleApp`) imports Sparkle. `CapsuleUI` owns a `@MainActor`
protocol `UpdaterDriving` (canCheckForUpdates / automaticallyChecksForUpdates get-set /
checkForUpdates / lastUpdateCheckDate / onStateChange) and an `@Observable UpdaterModel` that
binds the UI. Tests inject `StubUpdaterDriver`; previews use `DisabledUpdaterDriver`. This
keeps Sparkle out of `swift test`’s effective use (it links but no test needs a live updater)
and honors the layering rule (UI imports no backend; Sparkle is neither). Confirmed: Sparkle
2.9.3 resolves as a signed binary xcframework and links under the CLT toolchain; 790 tests
stay green.

### D2 — Info.plist Sparkle keys with clearly-marked release placeholders
`SUFeedURL` → the GitHub-hosted `appcast.xml`; `SUEnableAutomaticChecks` → true;
`SUScheduledCheckInterval` → 86400; `SUPublicEDKey` → a placeholder with an XML comment
instructing the releaser to paste the real EdDSA public key (from
`generate_keys`). A placeholder key is safe: Sparkle simply rejects unsigned feeds until the
real key + private key (in the release runner’s keychain) are in place.

### D3 — Unsandboxed Sparkle needs no extra entitlements
Hardened Runtime is already enabled; the app is unsandboxed. Sparkle’s XPC services exist only
for the sandboxed case, so v1 uses the simple in-process installer. Entitlements stay empty of
Sparkle-specific keys; a comment records why.

### D4 — Release pipeline: composable scripts + thin Makefile + guarded workflow
`Scripts/release/*.sh` — `build.sh` (xcodebuild archive/export, Release config), `sign.sh`
(inside-out codesign, `--options runtime`, entitlements), `notarize.sh` (`notarytool submit
--wait` + `stapler staple`), `package.sh` (zip + DMG), `appcast.sh` (Sparkle
`generate_appcast`). A top `release.sh` orchestrates and honors `--dry-run`. `Makefile` gains
`archive/sign/notarize/staple/release/coverage` targets replacing the `package` echo stub.
`.github/workflows/release.yml` runs on `v*` tags, imports the Developer ID cert from secrets,
and only performs signing steps when secrets are present.

### D5 — Privacy page: a pure-Swift `PrivacyDisclosure` model rendered by `PrivacyView`
The collected/never-collected content is a testable value type (`PrivacyDisclosure` with
`CollectedItem`/`NeverCollectedItem` arrays) in CapsuleDomain; `PrivacyView` (CapsuleUI)
renders it and is reachable from the About/Diagnostics surface and Preferences. A
“Copy bug-report info” action assembles Capsule version + `container system version` + macOS
version + a diagnostic-bundle summary — the same fields the issue template requires — via a
`BugReportInfo` assembler tested against `MockBackend`.

### D6 — Contributor contract mirrors the enforced architecture
`CONTRIBUTING.md` gets: an architecture map (module table + dependency arrows + the two
enforced boundaries), code-style rules (swift-format, license headers, layering, naming,
test-first expectation, no force-unwrap in non-test code), and a screenshot-update policy
(where docs images live, when a UI change must refresh them, how to regenerate). `CODEOWNERS`
splits ownership by path into UI shell, backend adapter, automation, and release pipeline.
Issue forms (`bug_report.yml`, `feature_request.yml`, `config.yml`) + a PR template; the bug
form has *required* fields for the four diagnostic facts.

### D7 — Tests: fill unit gaps, add golden XCUITest flows, wire coverage
New unit tests cover the milestone’s pure-Swift additions: `UpdaterModel`/stub-driver contract,
`PrivacyDisclosure`, `BugReportInfo` (against MockBackend), and any release version helper.
Golden UI tests (XCUITest) drive the app launched in a deterministic **UI-test mode** (a
`--uitest` launch argument injects `MockBackend` + fixed seed data) and assert on accessibility
identifiers for: build sheet, run sheet, an inspector, an error state, and settings. Coverage:
`make coverage` runs `swift test --enable-code-coverage` and emits an `llvm-cov` summary +
lcov; CI (re-enabled from `.disabled`) adds a coverage step and an unsigned app-build + UI-test
job. Integration tests remain self-skipping unless `CAPSULE_INTEGRATION=1`.

## Acceptance mapping

| Acceptance item | How it’s met | Fully executable here? |
| --- | --- | --- |
| Signed/notarized/stapled build from the pipeline | Scripts + Makefile + release.yml; dry-run proves the plan | Machinery yes; real artifact needs Developer ID |
| Sparkle delivers an update end-to-end (unsandboxed) | Full integration + appcast script; unit-tested seam | Integration yes; real update needs hosting |
| CONTRIBUTING/CODEOWNERS/issue templates; bug template auto-requests version+diagnostics | Files created; bug form requires the four facts | Yes |
| Unit + golden UI tests pass in CI; integration gated; coverage runs | New tests + re-enabled CI + coverage target | Unit/coverage yes; UI tests compile + run via `make app` |
