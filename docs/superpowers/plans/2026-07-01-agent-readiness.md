# Agent-readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Capsule repo agent-ready: a lean `CLAUDE.md` playbook, a thin `AGENTS.md` pointer, four project subagents under `.claude/agents/`, a README logo header reusing the app icon, and light CONTRIBUTING/PR-template edits.

**Architecture:** Documentation-only change (no Swift). `README.md`/`CONTRIBUTING.md` stay the single source of truth; every new file *links* to them and carries only the operational delta (exact file paths, seam names, checklists). Spec: `docs/superpowers/specs/2026-07-01-agent-readiness-design.md`.

**Tech Stack:** Markdown, YAML frontmatter (Claude Code subagent format), `make check`/`make test` as the regression gate.

## Global Constraints

- **No duplication:** new docs link to `README.md`/`CONTRIBUTING.md` anchors; never paste the recipe steps or the edge list verbatim.
- **`architecture-guardian` is read-only:** its frontmatter `tools` line is exactly `Read, Grep, Glob, Bash` — no `Edit`, no `Write`.
- **No new CI**, no new `make` targets or scripts, **no issue-template or CODEOWNERS edits**.
- **Logo is a byte-for-byte copy** of `App/Assets.xcassets/AppIcon.appiconset/icon_1024.png` (`cp`, no re-encode).
- **The tagline appears exactly once in `README.md`** after the header edit (no leftover plaintext subtitle).
- All new/edited files are Markdown or PNG → `make check && make test` must stay green untouched (`check-headers.sh` scans only `*.swift`; `swift-format` runs only over `FORMAT_PATHS`).
- Commit after each task. The repo pre-commit hook (license headers) passes automatically for non-Swift files.

---

### Task 1: Logo asset + README header

**Files:**
- Create: `docs/assets/capsule-logo.png` (copy of `App/Assets.xcassets/AppIcon.appiconset/icon_1024.png`)
- Modify: `README.md:1-5`

**Interfaces:**
- Consumes: nothing.
- Produces: `docs/assets/capsule-logo.png` (referenced by the README `<img>`); README keeps the `## Architecture` heading (anchor `#architecture`) that Task 6 links to.

- [ ] **Step 1: Copy the icon byte-for-byte**

```bash
mkdir -p docs/assets
cp App/Assets.xcassets/AppIcon.appiconset/icon_1024.png docs/assets/capsule-logo.png
```

- [ ] **Step 2: Verify the copy and that it is not gitignored**

Run: `cmp App/Assets.xcassets/AppIcon.appiconset/icon_1024.png docs/assets/capsule-logo.png && echo IDENTICAL`
Expected: `IDENTICAL`

Run: `git check-ignore docs/assets/capsule-logo.png; echo "ignore-exit=$?"`
Expected: no path printed, `ignore-exit=1` (not ignored)

- [ ] **Step 3: Replace README lines 1–5 with the centered header**

The current `README.md` begins with exactly these five lines (title, blank, two-line subtitle, blank):

```markdown
# Capsule

A native macOS app for managing containers, backed by a command-line container
runtime.

```

Replace that whole block (through the blank line 5) with the block below **followed by exactly one blank line**, so `## Supported runtime envelope` remains the first body heading:

```html
<div align="center">
  <img src="docs/assets/capsule-logo.png" alt="Capsule app icon" width="128" height="128" />
  <h1>Capsule</h1>
  <p><strong>A native macOS app for managing containers, backed by a command-line container runtime.</strong></p>
</div>
```

Use a single Edit with `old_string` = the five original lines and `new_string` = the `<div>` block + one trailing blank line. Do **not** leave the old plaintext subtitle in place — the tagline must not render twice.

- [ ] **Step 4: Verify the tagline appears exactly once and the old title is gone**

Run: `grep -c "A native macOS app for managing containers" README.md`
Expected: `1`

Run: `grep -c '^# Capsule' README.md; true`
Expected: `0`

Run: `sed -n '1p;7p' README.md`
Expected: line 1 is `<div align="center">`; line 7 is `## Supported runtime envelope`

- [ ] **Step 5: Commit**

```bash
git add docs/assets/capsule-logo.png README.md
git commit -m "docs(readme): centered logo header from the app icon

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JYNmieH7AYvXys56bV8B7p"
```

---

### Task 2: `command-adder` subagent

**Files:**
- Create: `.claude/agents/command-adder.md`

**Interfaces:**
- Consumes: `CONTRIBUTING.md#adding-a-command-without-touching-the-ui` (existing anchor).
- Produces: subagent name `command-adder` (referenced by Tasks 6 and 7 by that exact name).

- [ ] **Step 1: Write the file with exactly this content**

```markdown
---
name: command-adder
description: >-
  Use when adding or extending a `container` command in Capsule — e.g. "add a
  pause command", "wire up `container network rm`", "expose stats from the
  domain". Drives the full end-to-end recipe INCLUDING its argv tests. For
  standalone test work on existing code, use test-author instead.
tools: Read, Grep, Glob, Edit, Write, Bash
---

You add `container` commands to Capsule end-to-end without touching any view.

**Canonical recipe:** follow
[CONTRIBUTING.md → Adding a command without touching the UI](../../CONTRIBUTING.md#adding-a-command-without-touching-the-ui).
The map below is the concrete, post-M11 file layout for that recipe — not a replacement for it.

## File map

- **Step 1 — Domain:** add a `ResourceAction` case + matching `verb` string in
  `Sources/CapsuleDomain/Action.swift`.
- **Step 2 — Port:** declare the async method on `ContainerBackend` in
  `Sources/CapsuleBackend/ContainerBackend.swift` (side-effects `async throws`; reads return
  value types or `Parsed<T>`; streaming returns `AsyncThrowingStream<OutputLine, Error>`).
- **Step 3a — argv factory:** add a `static func … -> [String]` to
  `Sources/CapsuleBackend/CLICommand.swift` (relocated here in M11 — NOT the CLI-backend
  module), built with `ArgumentBuilder(…).adding/.flag/.option`. Flags mirror `container` v1.0.0.
- **Step 3b — adapter:** implement the protocol method in
  `Sources/CapsuleCLIBackend/CLIContainerBackend.swift` using the canonical
  `runChecked(CLICommand.…)` pattern; decode reads via `OutputParser` in
  `Sources/CapsuleCLIBackend/OutputParser.swift`. Go through `runChecked` so non-zero exit is a
  failure. Deliberate bypasses only: prune-style/`systemStatus`, the `runRaw`/`streamRaw`
  escape hatches, and the secret-feeding `runLogin` path — `runChecked` takes no
  `standardInput`, so a secret-bearing command follows the `runLogin` pattern
  (`runner.run(argv, environment:standardInput:)` + manual `BackendError.nonZeroExit`
  mapping). *(3a + 3b together are the recipe's single "step 3", which M11 split across two
  modules.)*
- **Step 4 — mock:** mirror the behavior in `Sources/CapsuleBackend/MockBackend.swift` by
  mutating seeded state via `withState { … }` and recording typed inputs on a `lastXxx` spy
  property. `MockBackend` never builds argv.
- **Step 5 — domain orchestration:** surface it from the relevant `@Observable` model; views
  never change.

## Caveats the recipe doesn't spell out

- The recipe's "ProcessRunner" is really the `ProcessRunning` protocol
  (`Sources/CapsuleCLIBackend/ProcessRunning.swift`) implemented by `CLIProcessRunner`; there is
  no type literally named `ProcessRunner`. `ArgumentBuilder` is only `CLICommand`'s low-level
  primitive.
- A secret-bearing command puts `--password-stdin` on argv and feeds the secret via
  `standardInput` — never on argv.
- Every conformer must be updated: both `CLIContainerBackend` and `MockBackend` (plus the
  `CapsuleAutomation` driver surface) or the build breaks.
- Tests are part of the change — follow the `test-author` conventions: a Form-A `CLICommand`
  factory test is always required; a Form-B `CLIContainerBackend` + `StubProcessRunner` test is
  required only when the adapter decodes/streams/maps non-zero-exit or handles a secret.

## Checklist (run before you claim done)

1. `ResourceAction` case + `verb` added.
2. `ContainerBackend` method declared.
3. `CLICommand` factory added in `CapsuleBackend`; adapter method added in `CapsuleCLIBackend`
   via `runChecked`/`OutputParser`.
4. `MockBackend` mirrors it (state mutation + `lastXxx` spy).
5. Domain model exposes it; no view code changed.
6. argv tests added (Form A always; Form B when the adapter decodes/streams/maps errors or
   handles a secret — the secret variant asserts the secret is absent from `stub.lastCall`).
7. `make check && make test` green.
```

- [ ] **Step 2: Verify frontmatter**

Run: `head -n 1 .claude/agents/command-adder.md && grep '^name:' .claude/agents/command-adder.md && grep '^tools:' .claude/agents/command-adder.md`
Expected: `---`, `name: command-adder`, `tools: Read, Grep, Glob, Edit, Write, Bash`

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/command-adder.md
git commit -m "docs(agents): add command-adder subagent

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JYNmieH7AYvXys56bV8B7p"
```

---

### Task 3: `architecture-guardian` subagent (read-only)

**Files:**
- Create: `.claude/agents/architecture-guardian.md`

**Interfaces:**
- Consumes: `CONTRIBUTING.md#enforced-boundaries-non-negotiable` (existing anchor).
- Produces: subagent name `architecture-guardian` (referenced by Tasks 6 and 7).

- [ ] **Step 1: Write the file with exactly this content**

```markdown
---
name: architecture-guardian
description: >-
  Use to review a Capsule change for layering, boundary, and secret-handling
  violations before merge — e.g. "check this diff doesn't break the boundaries",
  "did I leak a secret onto argv?". Read-only reviewer: reports, never edits.
tools: Read, Grep, Glob, Bash
---

You review Capsule changes for boundary, layering, and secret-handling violations. You are
**read-only**: report findings and suggest fixes, but never edit files.

**Canonical rule:** the two headline layering rules live in
[CONTRIBUTING.md → Enforced boundaries](../../CONTRIBUTING.md#enforced-boundaries-non-negotiable);
they expand to the **eight** concrete forbidden import edges in `Scripts/check-architecture.sh`:
UI must not import {`CapsuleBackend`, `CapsuleCLIBackend`, `CapsuleTerminal`}; Domain must not
import {`CapsuleUI`, `CapsuleCLIBackend`, `CapsuleTerminal`}; Terminal must not import
{`CapsuleBackend`, `CapsuleCLIBackend`}.

## Facts you enforce

- `CapsuleDomain` must not use `Foundation.Process` (grep `Process\s*\(`).
- The M11 relocation facts enforced only by
  `Tests/CapsuleUnitTests/ArchitectureGuardTests.swift`: `CapsuleBackend` must be Process-free
  and own `CLICommand.swift` + `ArgumentBuilder.swift`; `CapsuleCLIBackend` must NOT own those
  but must own `CLIProcessRunner.swift` (the sole `Foundation.Process` user).
- A deliberate new edge requires updating **both** `Scripts/check-architecture.sh` and
  `Tests/CapsuleUnitTests/ArchitectureGuardTests.swift`.
- Secrets: no password/token ever reaches argv (`--password-stdin` + stdin only); redaction via
  `SecretRedactor` (Diagnostics, placeholder `‹redacted›`) and `CommandRedactor` (Domain) — do
  not conflate them.
- UI localization/color rules are advisory pointers to `swiftui-view-builder`; your hard checks
  are imports, `Process`, and secrets.

## Checklist (read-only — report, never apply)

1. `grep` touched `CapsuleUI` files for `import CapsuleBackend` / `import CapsuleCLIBackend` /
   `import CapsuleTerminal`.
2. `grep` touched `CapsuleDomain` files for `import CapsuleUI` / `import CapsuleCLIBackend` /
   `import CapsuleTerminal` and `Process(`.
3. `grep` touched `CapsuleTerminal` files for `import CapsuleBackend` /
   `import CapsuleCLIBackend` (all eight edges covered by your own grep pass, not just by
   `make check`).
4. Confirm any new `CLICommand`/`ArgumentBuilder` code landed in `CapsuleBackend`, adapter code
   in `CapsuleCLIBackend`.
5. Scan for secrets on argv; confirm the stdin path is used.
6. Always run `make check`. Run `make test` only if `make check`/the package builds cleanly; if
   the tree does not build, report that and skip `make test` — never treat its absence as a
   pass. Suggest fixes; apply none.
```

- [ ] **Step 2: Verify frontmatter is read-only**

Run: `grep '^tools:' .claude/agents/architecture-guardian.md`
Expected: `tools: Read, Grep, Glob, Bash` (must NOT contain `Edit` or `Write`)

Run: `grep '^tools:' .claude/agents/architecture-guardian.md | grep -cE 'Edit|Write'; true`
Expected: `0`

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/architecture-guardian.md
git commit -m "docs(agents): add architecture-guardian subagent (read-only)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JYNmieH7AYvXys56bV8B7p"
```

---

### Task 4: `swiftui-view-builder` subagent

**Files:**
- Create: `.claude/agents/swiftui-view-builder.md`

**Interfaces:**
- Consumes: `CONTRIBUTING.md#code-style-rules` (existing anchor).
- Produces: subagent name `swiftui-view-builder` (referenced by Tasks 6 and 7).

- [ ] **Step 1: Write the file with exactly this content**

```markdown
---
name: swiftui-view-builder
description: >-
  Use when building or changing a CapsuleUI view, inspector, sheet, or banner —
  e.g. "add a Networks inspector tab", "build a prune confirmation sheet",
  "make this row accessible". Encodes Capsule's UI conventions.
tools: Read, Grep, Glob, Edit, Write, Bash
---

You build and change views in `Sources/CapsuleUI` to Capsule's house conventions. The canonical
concurrency/layering rules live in
[CONTRIBUTING.md → Code-style rules](../../CONTRIBUTING.md#code-style-rules); the concrete UI
idioms are below.

## Conventions you encode

- **Models:** observed models are `@MainActor @Observable` (`import Observation`, NOT SwiftUI
  `ObservableObject`/`@Published`) and live in `CapsuleDomain`. Inject via `init` as `let model`
  (read-only) or `@Bindable var model` (two-way); never construct in the view, never via
  `@Environment`/`@EnvironmentObject`. Local ephemeral state = `@State private var`.
- **Boundary:** `CapsuleUI` imports only SwiftUI, `CapsuleDomain`, AppKit, Foundation,
  Observation, UniformTypeIdentifiers — NEVER a Backend/Terminal module (enforced by
  `ArchitectureGuardTests`).
- **Localization:** every user-facing literal carries `bundle: .module`, e.g.
  `Text("Status", bundle: .module)`; proper nouns use `Text(verbatim:)`. Domain display enums
  get `.localizedTitle` accessors in `Sources/CapsuleUI/LocalizedDisplay.swift` via the
  `uiString(_:)` helper, with the default English string byte-for-byte identical to the Domain
  `title`.
- **Accessibility:** `.accessibilityLabel(Text("…", bundle: .module))`, `.accessibilityValue(…)`,
  `.accessibilityElement(children: .combine)` for composite banners, `.accessibilityHidden(true)`
  for decorative dots, `.accessibilityIdentifier(…)` for UI-test hooks. Use
  `CapsuleAccessibility.announce(_:)` for streaming/transcript VoiceOver updates. No
  `.accessibilityAddTraits(.isHeader)`; headers are structural via `Section`/`.font(.headline)`.
- **Dark mode / contrast:** no hardcoded hex palettes; derive from `CapsuleColors` semantic
  system colors. Tinted fills/borders read `@Environment(\.colorSchemeContrast)` and pass it
  into `CapsuleColors.softFill/bannerBackground/bannerBorder`.
- **Sheets:** plain structs taking closures (not models), driven from the parent via
  `.sheet(item:)` + an `Identifiable` enum; standardized chrome (`.padding(20)`, fixed
  `.frame(width:)`), Cancel = `role: .cancel` + `.keyboardShortcut(.cancelAction)`, confirm =
  `.borderedProminent` + `.keyboardShortcut(.defaultAction)`.
- **Inspectors:** `TabView` with a grouped Summary `Form` (`LabeledContent` rows) + a copyable
  monospaced Raw JSON tab that always renders the raw payload; empty/loading states use
  `ContentUnavailableView`.
- If a needed value type isn't on the domain model, STOP and route the backend work to
  `command-adder` rather than importing a backend module.

## Checklist (run before you claim done)

1. Model injected via init (`let`/`@Bindable`), from `CapsuleDomain`, `@Observable` (not
   `ObservableObject`).
2. No Backend/Terminal import added.
3. Every literal has `bundle: .module`; new enum labels added to `LocalizedDisplay.swift`
   byte-for-byte.
4. Accessibility label/value/hidden/identifier applied; announcements via
   `CapsuleAccessibility.announce`.
5. Colors from `CapsuleColors`; contrast threaded through where tinted.
6. Sheets closure-driven via `.sheet(item:)`.
7. `make check && make test` green (the arch guard test covers the import rule).
```

- [ ] **Step 2: Verify frontmatter**

Run: `grep '^name:' .claude/agents/swiftui-view-builder.md && grep '^tools:' .claude/agents/swiftui-view-builder.md`
Expected: `name: swiftui-view-builder`, `tools: Read, Grep, Glob, Edit, Write, Bash`

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/swiftui-view-builder.md
git commit -m "docs(agents): add swiftui-view-builder subagent

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JYNmieH7AYvXys56bV8B7p"
```

---

### Task 5: `test-author` subagent

**Files:**
- Create: `.claude/agents/test-author.md`

**Interfaces:**
- Consumes: nothing new.
- Produces: subagent name `test-author` (referenced by Tasks 2, 6, and 7). Its Form-A/Form-B rule is cited by `command-adder` (Task 2) and must stay identical in substance.

- [ ] **Step 1: Write the file with exactly this content**

```markdown
---
name: test-author
description: >-
  Use for standalone Capsule test work — adding or extending coverage on
  existing code, e.g. "cover this model's failure path", "add a golden UI
  check". Knows the unit / argv / golden-UI tiers and the mock/stub doubles.
  For tests that are part of wiring a NEW command end-to-end, use command-adder.
tools: Read, Grep, Glob, Edit, Write, Bash
---

You write Capsule tests in the right tier with the right doubles.

## The three tiers (two locations)

Tiers 1+2 are SwiftPM XCTest under `Tests/CapsuleUnitTests` (run via `make test`/`swift test`);
tier 3 golden XCUITest is `App/CapsuleUITests/CapsuleUITests.swift` (run via `xcodebuild`).
Integration tests live in `Tests/CapsuleIntegrationTests` (self-skip unless
`CAPSULE_INTEGRATION=1`). Pick the tier by SUT layer, not by folder.

- **Tier 1 (pure logic):** plain `XCTestCase`, `@testable import CapsuleDomain`, synchronous
  asserts on return values (model after `CIDRTests.swift`).
- **Tier 2 (argv) — the required-forms rule:**
  - *Form A* is ALWAYS required for a new/changed argv factory — a pure `CLICommand` factory
    test in `CLICommandTests.swift` (`import CapsuleBackend`) asserting the returned `[String]`
    exactly, e.g. `.stopContainer(id: "abc", options: .default) == ["stop", "abc"]`.
    `ArgumentBuilderTests.swift` (`@testable import CapsuleBackend`) pins the primitive incl.
    flag-omitted-when-nil / option-omitted-when-disabled.
  - *Form B* is required ONLY when the adapter does decoding, streaming, non-zero-exit mapping,
    or handles a secret; otherwise optional. It lives in `CLIContainerBackendTests.swift`
    (`@testable import CapsuleCLIBackend`): inject `StubProcessRunner` via the internal
    `makeBackend`/seam `init(executableURL:runner:)`, `try await` the method, assert
    `stub.lastCall`; seed `stub.result`/`stub.streamLines`/non-zero exit for decoding,
    streaming, and `BackendError.nonZeroExit` mapping; the secret variant asserts the secret is
    on `stub.lastStandardInput` and ABSENT from `stub.lastCall`. Never spawns a process.
- **Tier 3 (golden UI):** `@MainActor` tests driving `XCUIApplication`; must use
  `waitForExistence(timeout:)`; `continueAfterFailure = false`. Launch mock mode with
  `app.launchEnvironment["CAPSULE_UITEST"] = "1"` (read in `CapsuleScene.init` →
  `AppEnvironment.uiTest()`), scenario via `CAPSULE_UITEST_SCENARIO` (`healthy` | `serviceDown`;
  `serviceDown` → `MockBackend(systemRunState: .stopped)`). Depend on seeded fixtures by exact
  string (container `web`, image `docker.io/library/alpine:latest`) and accessibility
  identifiers (`sidebar-containers`, `system-health-banner`, `run-sheet`, …) — do not change
  seeds/identifiers casually.

## Doubles

- **`MockBackend`** (`Sources/CapsuleBackend/MockBackend.swift`): in-memory `ContainerBackend`;
  instantiate directly (optionally `MockBackend(systemRunState: .stopped)`,
  `MockBackend(sampleStats: …)`), `try await` methods, assert returned data or `lastXxx` spies.
  It never builds/asserts argv. `@MainActor` model tests default a
  `model(backend: any ContainerBackend = MockBackend())` factory.
- **`StubProcessRunner`**: records argv (`lastCall`) and stdin (`lastStandardInput`); seeds
  results/streams/exit codes. Tier-2 Form B only.

## Coverage

`Scripts/coverage.sh` (`make coverage`) runs only `swift test` with instrumentation; XCUITests
are excluded.

## Checklist (run before you claim done)

1. Tier picked by SUT layer.
2. Domain logic → Tier 1; new argv → Form A (always) + Form B (only per the rule above); model
   behavior → `@MainActor` + `MockBackend` (assert data or `lastXxx`).
3. Secret path → Form B asserting `stub.lastStandardInput` set and `stub.lastCall` clean.
4. UI flow → tier-3 golden test with `CAPSULE_UITEST` + `waitForExistence`, reusing seeded
   fixtures/identifiers.
5. `make test` green (and `make coverage` if coverage is the goal).
```

- [ ] **Step 2: Verify frontmatter**

Run: `grep '^name:' .claude/agents/test-author.md && grep '^tools:' .claude/agents/test-author.md`
Expected: `name: test-author`, `tools: Read, Grep, Glob, Edit, Write, Bash`

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/test-author.md
git commit -m "docs(agents): add test-author subagent

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JYNmieH7AYvXys56bV8B7p"
```

---

### Task 6: `CLAUDE.md` playbook + `AGENTS.md` pointer

**Files:**
- Create: `CLAUDE.md`
- Create: `AGENTS.md`

**Interfaces:**
- Consumes: the four subagent names/files from Tasks 2–5; anchors `README.md#architecture`, `CONTRIBUTING.md#enforced-boundaries-non-negotiable`, `CONTRIBUTING.md#adding-a-command-without-touching-the-ui` (all existing).
- Produces: `CLAUDE.md` (linked by Task 7's CONTRIBUTING subsection and by `AGENTS.md`).

- [ ] **Step 1: Write `CLAUDE.md` with exactly this content**

```markdown
# Capsule — agent playbook

Native macOS SwiftUI app that drives the `container` CLI through a strictly-layered Swift
Package.

## Source of truth

- [README.md](README.md) — runtime envelope, architecture, and the module dependency graph.
- [CONTRIBUTING.md](CONTRIBUTING.md) — code-style rules, the enforced boundaries, the
  [Adding a command without touching the UI](CONTRIBUTING.md#adding-a-command-without-touching-the-ui)
  recipe, and the *Before you push* checklist.

This file does not repeat those documents — when they disagree with anything here, they win.

## Read code selectively

**Do read the real files** before you touch a boundary, adapter, or parser; when you edit an
existing file; or when you are unsure of a convention. Useful anchors:

- `Sources/CapsuleBackend/CLICommand.swift` — every argv factory
- `Sources/CapsuleCLIBackend/CLIContainerBackend.swift` — the CLI adapter
- `Sources/CapsuleCLIBackend/OutputParser.swift` — output decoding
- `Sources/CapsuleBackend/MockBackend.swift` — the in-memory backend
- `Sources/CapsuleDomain/*Model.swift` — observable models
- `Sources/CapsuleUI/*View.swift` — views

**Skip deep reads** for mechanical or narrowly-localized changes: a rename within one file,
copy text, a single test mirroring an adjacent one.

Prefer `Grep`/`Glob` to locate the one right file over reading whole directories.

## Canonical commands

| Command | What it does |
| --- | --- |
| `make check` | lint + architecture + license headers (no build/test) |
| `make test` | `swift test` — unit tests (tiers 1+2) |
| `make app` | build the macOS `.app` bundle |
| `make run` | build and launch the app |
| `make format` | apply `swift-format` in place |
| `make coverage` | unit tests + lcov via `Scripts/coverage.sh`; does **not** run XCUITests |

**Rule: run `make check && make test` and see them pass before claiming a task is done.**
XCUITests run via `xcodebuild` against the built `.app` (CI job `app-ui-tests`), not
`swift test`.

## Non-negotiable boundaries

- `CapsuleUI` never imports a Backend module (`CapsuleBackend`, `CapsuleCLIBackend`) nor
  `CapsuleTerminal`. `CapsuleDomain` never imports `CapsuleUI`, `CapsuleCLIBackend`, or
  `CapsuleTerminal`, and never uses `Foundation.Process`.
- Enforced by `Scripts/check-architecture.sh` **and**
  `Tests/CapsuleUnitTests/ArchitectureGuardTests.swift`; a deliberate new edge means updating
  **both**. The authoritative rule lives in
  [CONTRIBUTING.md → Enforced boundaries](CONTRIBUTING.md#enforced-boundaries-non-negotiable).
- Secrets go over **stdin, never argv** (`--password-stdin`); redaction lives in
  `SecretRedactor` (Diagnostics) and `CommandRedactor` (Domain).

## Which subagent for which task

Project subagents live in [`.claude/agents/`](.claude/agents/):

| If the task is… | Use subagent | Because it knows… |
| --- | --- | --- |
| Add/extend a `container` command end-to-end (domain case → port → adapter → mock → argv tests) | `command-adder` | the recipe + the `CLICommand`/`CLIContainerBackend`/`MockBackend` seam |
| Review a diff for layering/secret/boundary violations (read-only) | `architecture-guardian` | the eight forbidden edges + guard test/script + stdin-secret rule |
| Build or change a SwiftUI view/inspector/sheet | `swiftui-view-builder` | `@Observable` injection, `bundle: .module`, `CapsuleColors`, accessibility idioms |
| Add or update tests (standalone) | `test-author` | tiers 1/2/3, `StubProcessRunner`, `MockBackend`, `CAPSULE_UITEST` mode |

## Module map

`CapsuleBackend` (the port + `MockBackend` + argv factories), `CapsuleDomain` (models/actions),
`CapsuleCLIBackend` (the `Process` adapter), `CapsuleUI` (SwiftUI views), `CapsuleTerminal`
(SwiftTerm/PTY), `CapsuleAutomation` (App Intents/AppleScript), `CapsuleDiagnostics` (logging,
diagnostics, redaction), `CapsuleApp` (composition root). The dependency graph lives in
[README.md → Architecture](README.md#architecture).
```

- [ ] **Step 2: Write `AGENTS.md` with exactly this content**

```markdown
# Agent guide

This repository's agent instructions live in **[CLAUDE.md](CLAUDE.md)** — start there.

`CLAUDE.md` covers orientation (README + CONTRIBUTING are the source of truth),
when to read code, the canonical `make` commands, the non-negotiable module
boundaries, and which subagent to use for which task.

Project subagents in [`.claude/agents/`](.claude/agents/):

- **command-adder** — add a `container` command end-to-end (domain → port → adapter → mock → argv tests).
- **architecture-guardian** — read-only reviewer for layering, secrets, and boundary violations.
- **swiftui-view-builder** — build CapsuleUI views/inspectors/sheets to Capsule's house conventions.
- **test-author** — write tests across the unit / argv / golden-UI tiers.
```

- [ ] **Step 3: Verify the anchors CLAUDE.md links to exist**

Run: `grep -c '^## Architecture$' README.md && grep -c '^### Enforced boundaries (non-negotiable)' CONTRIBUTING.md && grep -c '^## Adding a command without touching the UI' CONTRIBUTING.md && ls .claude/agents/ | wc -l | tr -d ' '`
Expected: `1`, `1`, `1`, `4`

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md AGENTS.md
git commit -m "docs(agents): add CLAUDE.md playbook + AGENTS.md pointer

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JYNmieH7AYvXys56bV8B7p"
```

---

### Task 7: CONTRIBUTING subsection + PR-template line

**Files:**
- Modify: `CONTRIBUTING.md:13-15` (insert between the runtime-envelope bullet and `## Architecture map`)
- Modify: `.github/PULL_REQUEST_TEMPLATE.md` (append last checklist item)

**Interfaces:**
- Consumes: `CLAUDE.md`, `AGENTS.md` (Task 6), the four subagent names (Tasks 2–5), and CONTRIBUTING's existing in-doc anchors.
- Produces: the `## Working with AI agents` section referenced by the PR-template line.

- [ ] **Step 1: Insert the CONTRIBUTING subsection**

The insertion point is the **only valid location**: between the runtime-envelope bullet block and `## Architecture map`. Use a single Edit with this exact `old_string`:

```markdown
  [README](README.md#supported-runtime-envelope).

## Architecture map
```

and this exact `new_string`:

```markdown
  [README](README.md#supported-runtime-envelope).

## Working with AI agents

Capsule ships an agent playbook so AI coding assistants stay inside the same
guardrails as human contributors.

- **[CLAUDE.md](CLAUDE.md)** is the lean playbook: orientation, when to read
  code, the canonical `make` commands, and which subagent to use for which task.
  It treats this file and the [README](README.md) as the source of truth and
  does not duplicate them. [AGENTS.md](AGENTS.md) is a thin pointer to it.
- **Project subagents** live in [`.claude/agents/`](.claude/agents/):
  `command-adder` (adds a `container` command end-to-end),
  `architecture-guardian` (read-only boundary/secret reviewer),
  `swiftui-view-builder` (CapsuleUI views), and `test-author` (tests).
- **The rules agents follow are the ones already enforced here** — the layering
  rules in [Enforced boundaries](#enforced-boundaries-non-negotiable), checked by
  `ArchitectureGuardTests` and `Scripts/check-architecture.sh`; a deliberate new
  edge means updating **both**.
- **Human review still gates merges.** Treat agent output like any other patch:
  run `make check && make test`, keep secrets off argv, and follow the
  [Adding a command without touching the UI](#adding-a-command-without-touching-the-ui)
  recipe. Note AI assistance in your PR (see the pull-request template).

## Architecture map
```

- [ ] **Step 2: Append the PR-template checklist line**

In `.github/PULL_REQUEST_TEMPLATE.md`, use a single Edit with this exact `old_string`:

```markdown
- [ ] User-facing strings routed through the String Catalog / `LocalizedDisplay`.
```

and this exact `new_string`:

```markdown
- [ ] User-facing strings routed through the String Catalog / `LocalizedDisplay`.
- [ ] If AI-assisted, output was reviewed against the boundaries in CONTRIBUTING.md ("Working with AI agents") and `make check && make test` pass.
```

- [ ] **Step 3: Verify placement**

Run: `grep -n '^## Working with AI agents$\|^## Architecture map$' CONTRIBUTING.md`
Expected: `Working with AI agents` on a lower line number than `Architecture map`, with no other heading between them except the subsection's own content.

Run: `grep -A2 'LocalizedDisplay' .github/PULL_REQUEST_TEMPLATE.md | grep -c 'If AI-assisted'`
Expected: `1`

- [ ] **Step 4: Commit**

```bash
git add CONTRIBUTING.md .github/PULL_REQUEST_TEMPLATE.md
git commit -m "docs(contributing): AI-agents section + PR-template line

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JYNmieH7AYvXys56bV8B7p"
```

---

### Task 8: Verification sweep (no commit)

**Files:** none (read-only verification per spec §6).

**Interfaces:**
- Consumes: everything from Tasks 1–7.
- Produces: a pass/fail report; the branch is merge-ready only if every step passes.

- [ ] **Step 1: Regression gate**

Run: `make check && make test`
Expected: both exit 0; the unit suite (801 tests) passes with 0 failures.

- [ ] **Step 2: Logo + README invariants**

Run: `cmp App/Assets.xcassets/AppIcon.appiconset/icon_1024.png docs/assets/capsule-logo.png && grep -c "A native macOS app for managing containers" README.md`
Expected: `cmp` silent (identical), grep prints `1`

- [ ] **Step 3: Agent-file frontmatter battery**

Run:
```bash
for f in command-adder architecture-guardian swiftui-view-builder test-author; do
  head -n 1 ".claude/agents/$f.md" | grep -q '^---$' && grep -q "^name: $f$" ".claude/agents/$f.md" && echo "$f OK"
done
grep '^tools:' .claude/agents/architecture-guardian.md
```
Expected: four `… OK` lines; final line `tools: Read, Grep, Glob, Bash`

- [ ] **Step 4: Anchor + cross-link battery**

Run:
```bash
grep -c '^## Working with AI agents$' CONTRIBUTING.md
grep -c 'CONTRIBUTING.md#enforced-boundaries-non-negotiable' CLAUDE.md
grep -c 'README.md#architecture' CLAUDE.md
grep -c 'CLAUDE.md' AGENTS.md
grep -c 'If AI-assisted' .github/PULL_REQUEST_TEMPLATE.md
grep -c 'CONTRIBUTING.md#adding-a-command-without-touching-the-ui' .claude/agents/command-adder.md
grep -c 'CONTRIBUTING.md#enforced-boundaries-non-negotiable' .claude/agents/architecture-guardian.md
grep -c 'CONTRIBUTING.md#code-style-rules' .claude/agents/swiftui-view-builder.md
grep -c '\.claude/agents/' CLAUDE.md
```
Expected: `1`, `1`, `1`, at least `1`, `1`, `1`, `1`, `1`, at least `1`

- [ ] **Step 5: Clean tree**

Run: `git status --short`
Expected: empty (everything committed; `.claude/scheduled_tasks.lock` and `.claude/worktrees/` must NOT be staged — only `.claude/agents/` was added).
