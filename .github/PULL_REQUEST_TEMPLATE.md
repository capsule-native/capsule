<!--
Thanks for contributing to Capsule! Keep PRs focused. See CONTRIBUTING.md for the
architecture map, code-style rules, and the screenshot-update policy.
-->

## What & why

<!-- What does this change and why? Link the issue it closes: "Closes #123". -->

## How it was tested

<!-- Commands you ran + what you observed. -->

- [ ] `make check` (lint + architecture + license headers) passes
- [ ] `make test` passes
- [ ] `make app` builds (if this touches the app target / Info.plist / entitlements)

## Checklist

- [ ] Stays inside the runtime envelope (Apple silicon, macOS 26+, unsandboxed, CLI-backed).
- [ ] Respects the layering (no new UI → Backend or Domain → UI/`Process` edge; if intentional,
      `ArchitectureGuardTests` **and** `Scripts/check-architecture.sh` were updated).
- [ ] Tests added/updated (unit for pure logic, argument-building for new CLI argv, golden UI
      for a new critical flow).
- [ ] No secret is written to argv, logs, or a diagnostic export outside the `DiagnosticOptions`
      opt-in.
- [ ] Screenshots under `docs/` refreshed if this changes visible UI (see the screenshot policy).
- [ ] User-facing strings routed through the String Catalog / `LocalizedDisplay`.

## Screenshots

<!-- Before/after for any visible UI change (light + dark where appearance-sensitive). -->
