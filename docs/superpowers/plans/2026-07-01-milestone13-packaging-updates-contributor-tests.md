# Milestone 13 — Implementation plan

_Spec: [design](../specs/2026-07-01-milestone13-packaging-updates-contributor-tests-design.md)_

Baseline verified: `make build` green, `make test` = 790 tests / 0 failures / 8 skipped.
Sparkle 2.9.3 already added to `Package.swift` + `Package.resolved` and confirmed to resolve
and link under the CLT toolchain with tests still green.

## Phase A — Contributor contract (docs; no Swift)
- Expand `CONTRIBUTING.md`: architecture map (module table + arrows + the two enforced
  boundaries), code-style rules, screenshot-update policy, release/version conventions.
- `.github/CODEOWNERS`: UI shell, backend adapter, automation layer, release pipeline.
- `.github/ISSUE_TEMPLATE/bug_report.yml` (required: Capsule version, `container system
  version`, host macOS, diagnostic bundle), `feature_request.yml`, `config.yml`.
- `.github/PULL_REQUEST_TEMPLATE.md`.
- **Verify:** files exist; bug form requires the four facts; YAML parses.

## Phase B — Sparkle updater + privacy page (Swift + Info.plist)
- Move `UpdaterController`/`NoopUpdaterController` from CapsuleApp → CapsuleUI (`Updater/`),
  class-bind the protocol, add `automaticallyChecksForUpdates` (get/set) +
  `lastUpdateCheckDate`. Keep it Sparkle-free.
- `CapsuleApp/Updates/SparkleUpdaterController.swift`: wraps `SPUStandardUpdaterController`;
  the only `import Sparkle`. Wire it into `AppEnvironment.live()` (replaces `NoopUpdaterController`).
- `CapsuleUI/UpdatesSettingsView.swift` + `PrivacyView.swift`; add both as Preferences tabs
  (thread `updater` + an `onExportDiagnostics`/privacy model through `CapsuleScene.Settings`).
- `CapsuleDomain/PrivacyDisclosure.swift`: testable value type (collected / never-collected).
- Info.plist: `SUFeedURL`, `SUEnableAutomaticChecks`, `SUScheduledCheckInterval`,
  `SUPublicEDKey` (placeholder + comment). Entitlements: comment why no Sparkle keys needed.
- **Verify:** `make build` + `make test` green; new unit tests for `PrivacyDisclosure`,
  the updater seam (stub driver), and a `BugReportInfo` assembler pass; `make app` builds a
  bundle that links Sparkle.

## Phase C — Release pipeline + CI + coverage
- `Scripts/release/{build,sign,notarize,package,appcast,release}.sh` — `set -euo pipefail`,
  `--dry-run`, clear failure when Developer ID / notary creds absent. Inside-out codesign
  with `--options runtime` + entitlements; `notarytool submit --wait` + `stapler staple`;
  zip + DMG; Sparkle `generate_appcast`.
- `Makefile`: replace the `package` echo stub with `archive/sign/notarize/staple/release`;
  add `coverage` (`swift test --enable-code-coverage` + `llvm-cov` summary + lcov).
- `.github/workflows/ci.yml` (re-enabled from `.disabled`): add coverage step + an unsigned
  app-build + UI-test job; integration tests stay gated.
- `.github/workflows/release.yml`: on `v*` tag — build/sign/notarize/staple/package/appcast,
  upload artifact + GitHub release; signing steps guarded on secrets.
- **Verify:** `bash -n` + `shellcheck` clean; `release.sh --dry-run` prints the plan and exits
  0; `make coverage` emits a report; workflow YAML parses.

## Phase D — Golden UI tests
- Deterministic UI-test mode: `AppEnvironment.assemble(backend:executablePath:)` extracted;
  `launch()` picks `MockBackend` under `CAPSULE_UITEST=1` (+ a scenario env for error states).
- Accessibility identifiers on: sidebar sections, Run/Build toolbar buttons + sheet fields +
  primary buttons, an inspector, the Settings tabs, the error/ContentUnavailable surface.
- `App/CapsuleUITests`: golden flows — launch, containers list, Run sheet, Build sheet,
  Settings tabs, service-down error banner.
- **Verify:** UITest bundle compiles via `make app`; run attempt via `xcodebuild test`.

## Phase E — Review, verify, finish
- Adversarial 3-lens review (subagents): correctness, security (signing/redaction/secrets),
  layering. Fix findings.
- Final: `make ci` green, `make coverage`, `make app`, dry-run pipeline, live GUI smoke.
- Merge to `main` locally (no push/PR). Update memory.
