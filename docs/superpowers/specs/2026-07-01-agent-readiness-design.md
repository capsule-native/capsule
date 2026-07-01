# Agent-readiness for Capsule

Date: 2026-07-01 · Status: Approved design

## 1. Overview / goal

Capsule is a mature native macOS SwiftUI app (13 milestones, 801 tests) with a strictly-layered
Swift Package, a thin XcodeGen app target, test-enforced module boundaries, and thorough
`README.md` + `CONTRIBUTING.md`. This spec makes the repo *agent-ready*: it adds a lean `CLAUDE.md`
playbook, a thin `AGENTS.md` pointer, four focused project subagents under `.claude/agents/`, a
short contribution note, and a logo header on the README — **without duplicating existing docs or
adding any new CI.** The guiding principle: `README.md` and `CONTRIBUTING.md` remain the single
source of truth; every new file *links* to them (and to the enforcement scripts/tests) rather than
restating their content, so nothing drifts.

## 2. Current state

Grounded in the real repo:

- **Docs already excellent.** `README.md` (runtime envelope + `## Architecture` with the module
  dependency graph) and `CONTRIBUTING.md` (Runtime envelope → Architecture map → Enforced
  boundaries → *Adding a command without touching the UI* → Code-style → Screenshot policy →
  Before you push → Releases → Reporting bugs) exist and are authoritative.
- **Boundaries are enforced, twice.** `Scripts/check-architecture.sh` (eight `forbid_import` edges
  + a `Foundation.Process` ban in `CapsuleDomain`) and
  `Tests/CapsuleUnitTests/ArchitectureGuardTests.swift` (substring guards + the M11 relocation
  facts) enforce the layering. `Makefile` wires `check = lint arch headers` and
  `ci = build lint arch headers test`; `.github/workflows/ci.yml` runs
  `make lint/arch/headers/build/coverage/xcodeproj`.
- **License headers cover Swift only.** `Scripts/check-headers.sh` scans `*.swift` under
  `Sources Tests App/Sources App/CapsuleUITests` for the literal `Copyright ©` in the first 8
  lines. Root-level Markdown is never scanned — so new `.md` files carry no header burden.
- **No agent scaffolding yet.** `CLAUDE.md` and `AGENTS.md` do **not** exist. `.claude/` is
  untracked but **not** gitignored, and `.claude/agents/` does not exist. `docs/assets/` does not
  exist.
- **App icon present.** `App/Assets.xcassets/AppIcon.appiconset/icon_1024.png` (1024×1024, ~340 KB)
  is a suitable logo source.
- **CODEOWNERS routing (placeholders).** `.github/CODEOWNERS` routes root/`.claude/` files and
  `CONTRIBUTING.md` to `@capsule-maintainers` via the `*` fallback;
  `.github/PULL_REQUEST_TEMPLATE.md` is owned by `@capsule-release`. These teams are placeholders
  and only bind once branch protection + real teams exist.

## 3. Approved decisions

1. **Four project subagents** in `.claude/agents/`: `command-adder`, `architecture-guardian`
   (read-only reviewer — **no** Edit/Write tools), `swiftui-view-builder`, `test-author`.
2. **`CLAUDE.md` is a lean playbook that links to `README.md`/`CONTRIBUTING.md`** as the source of
   truth and never duplicates them; **`AGENTS.md` is a thin pointer to `CLAUDE.md`**.
3. **Logo reuses the existing app icon:** copy
   `App/Assets.xcassets/AppIcon.appiconset/icon_1024.png` → `docs/assets/capsule-logo.png`, and
   center it with a "Capsule" wordmark + the existing tagline atop `README.md`.
4. **Contribution docs get a light touch:** a short `## Working with AI agents` subsection in
   `CONTRIBUTING.md` (routes to `@capsule-maintainers`) and one AI-assisted checklist line in
   `.github/PULL_REQUEST_TEMPLATE.md` (routes to `@capsule-release`).

## 4. Detailed design

### 4.1 `CLAUDE.md` (new) — detailed outline

A short playbook (target ≤ ~90 lines). It **links** to `README.md` / `CONTRIBUTING.md` for
anything substantive and never restates the module graph, code-style rules, or the command recipe
in full. Sections, with concrete bullet content:

**Title + one-liner.** `# Capsule — agent playbook`, one sentence: "Native macOS SwiftUI app that
drives the `container` CLI through a strictly-layered Swift Package."

**Orientation (source of truth).** *(Paths below are shown as they will appear in `CLAUDE.md`,
which lives at the repo root — root-relative, no `../`.)*
- Read `[README.md](README.md)` for the runtime envelope, architecture, and module dependency graph.
- Read `[CONTRIBUTING.md](CONTRIBUTING.md)` for code-style rules, the enforced boundaries, the
  *Adding a command without touching the UI* recipe, and the *Before you push* checklist.
- "This file does not repeat those documents — when they disagree with anything here, they win."

**Read code selectively.**
- **Do read the real files** before you touch a boundary/adapter/parser, when editing an existing
  file, or when unsure of a convention. Named anchors: `Sources/CapsuleBackend/CLICommand.swift`,
  `Sources/CapsuleCLIBackend/CLIContainerBackend.swift`,
  `Sources/CapsuleCLIBackend/OutputParser.swift`, `Sources/CapsuleBackend/MockBackend.swift`,
  `Sources/CapsuleDomain/*Model.swift`, `Sources/CapsuleUI/*View.swift`.
- **Skip deep reads** for mechanical or narrowly-localized changes (rename within one file, copy
  text, add a single test mirroring an adjacent one).
- Prefer `Grep`/`Glob` to locate the one right file over reading whole directories.

**Canonical commands.**
- `make check` — lint + arch + headers (no build/test).
- `make test` — `swift test` (unit tiers 1+2).
- `make app` — build the macOS `.app` bundle · `make run` — build and launch.
- `make format` — apply `swift-format`.
- `make coverage` — `Scripts/coverage.sh` (SwiftPM unit tests + lcov; does **not** run XCUITests).
- **Rule:** run **`make check && make test`** and see them pass before claiming a task is done.
  XCUITests run via `xcodebuild` against the built `.app` (CI job `app-ui-tests`), not `swift test`.

**Non-negotiable boundaries (linked, not copied).**
- `CapsuleUI` never imports a Backend module (`CapsuleBackend`/`CapsuleCLIBackend`) nor
  `CapsuleTerminal`; `CapsuleDomain` never imports `CapsuleUI`/`CapsuleCLIBackend`/`CapsuleTerminal`
  and never uses `Foundation.Process`.
- Enforced by `Scripts/check-architecture.sh` **and**
  `Tests/CapsuleUnitTests/ArchitectureGuardTests.swift`; a deliberate new edge means updating
  **both**. See `[CONTRIBUTING.md → Enforced boundaries](CONTRIBUTING.md#enforced-boundaries-non-negotiable)`
  for the authoritative rule.
- Secrets go over **stdin, never argv** (`--password-stdin`); redaction lives in `SecretRedactor`
  (Diagnostics) / `CommandRedactor` (Domain).

**Which subagent for which task.** A table:

| If the task is… | Use subagent | Because it knows… |
| --- | --- | --- |
| Add/extend a `container` command end-to-end (domain case → port → adapter → mock → argv tests) | `command-adder` | the recipe + the `CLICommand`/`CLIContainerBackend`/`MockBackend` seam |
| Review a diff for layering/secret/boundary violations (read-only) | `architecture-guardian` | the eight forbidden edges + guard test/script + stdin-secret rule |
| Build or change a SwiftUI view/inspector/sheet | `swiftui-view-builder` | `@Observable` injection, `bundle: .module`, `CapsuleColors`, accessibility idioms |
| Add or update tests (standalone) | `test-author` | tiers 1/2/3, `StubProcessRunner`, `MockBackend`, `CAPSULE_UITEST` mode |

**Module map.** One paragraph naming the modules (`CapsuleBackend` port, `CapsuleDomain`,
`CapsuleCLIBackend` adapter, `CapsuleUI`, `CapsuleTerminal`, `CapsuleAutomation`,
`CapsuleDiagnostics`, `CapsuleApp`) with a link to the README's dependency graph at
`[README.md#architecture](README.md#architecture)` — **not** a reproduction of it.

### 4.2 `AGENTS.md` (new) — full intended content

The file is tiny and is delivered verbatim:

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

### 4.3 The four subagents (`.claude/agents/*.md`, new)

Each file is a Markdown document with YAML frontmatter (`name`, `description`, `tools`) followed by
the body. Descriptions use natural trigger phrasing so the agent is auto-selected.

**Anti-duplication rule for all four bodies.** To honor §1's single-source-of-truth principle, each
subagent body **links** to its canonical `CONTRIBUTING.md`/`README.md` anchor for the *conceptual*
recipe and the *authoritative* boundary list, and encodes only the **operational delta** an agent
needs on top of that doc: the exact post-M11 file paths, the concrete seam/type names, the naming
caveats the prose doesn't spell out, and a run checklist. Subagent bodies must **not** paste the
recipe steps or the edge list verbatim — they cite them. (This keeps them from silently rotting
when `CONTRIBUTING.md` changes.)

#### 4.3.1 `command-adder.md`

Frontmatter:
```yaml
---
name: command-adder
description: >-
  Use when adding or extending a `container` command in Capsule — e.g. "add a
  pause command", "wire up `container network rm`", "expose stats from the
  domain". Drives the full end-to-end recipe INCLUDING its argv tests. For
  standalone test work on existing code, use test-author instead.
tools: Read, Grep, Glob, Edit, Write, Bash
---
```

Body — links + operational delta (no verbatim recipe):
- **Canonical recipe:** follow
  [`CONTRIBUTING.md` → *Adding a command without touching the UI*](../../CONTRIBUTING.md#adding-a-command-without-touching-the-ui).
  The steps below are the concrete, post-M11 file map for that recipe — not a replacement for it.
- **Step 1 — Domain:** add a `ResourceAction` case + matching `verb` string in
  `Sources/CapsuleDomain/Action.swift`.
- **Step 2 — Port:** declare the async method on `ContainerBackend` in
  `Sources/CapsuleBackend/ContainerBackend.swift` (side-effects `async throws`; reads return value
  types or `Parsed<T>`; streaming returns `AsyncThrowingStream<OutputLine, Error>`).
- **Step 3a — argv factory:** add a `static func … -> [String]` to
  **`Sources/CapsuleBackend/CLICommand.swift`** (relocated here in M11 — NOT the CLI-backend
  module), built with `ArgumentBuilder(…).adding/.flag/.option`. Flags mirror `container` v1.0.0.
- **Step 3b — adapter:** implement the protocol method in
  `Sources/CapsuleCLIBackend/CLIContainerBackend.swift` using the canonical
  `runChecked(CLICommand.…)` pattern; decode reads via `OutputParser` in
  `Sources/CapsuleCLIBackend/OutputParser.swift`. Treat non-zero exit as failure by going through
  `runChecked`. Deliberate bypasses only: prune-style/`systemStatus`, the `runRaw`/`streamRaw`
  escape hatches, and the secret-feeding `runLogin` path — `runChecked` takes no `standardInput`,
  so a secret-bearing command follows the `runLogin` pattern
  (`runner.run(argv, environment:standardInput:)` + manual `BackendError.nonZeroExit` mapping).
  *(3a + 3b together are the recipe's single "step 3", which M11 split across two modules.)*
- **Step 4 — mock:** mirror behavior in `Sources/CapsuleBackend/MockBackend.swift` by mutating
  seeded state via `withState { … }` and recording typed inputs on a `lastXxx` spy prop.
  `MockBackend` never builds argv.
- **Step 5 — domain orchestration:** surface it from the relevant `@Observable` model; views never
  change.
- **Naming caveats (not obvious from the recipe):** the recipe's "ProcessRunner" is really the
  `ProcessRunning` protocol (`Sources/CapsuleCLIBackend/ProcessRunning.swift`) implemented by
  `CLIProcessRunner`; there is no type literally named `ProcessRunner`. `ArgumentBuilder` is only
  `CLICommand`'s low-level primitive.
- **Secrets:** a secret-bearing command puts `--password-stdin` on argv and feeds the secret via
  `standardInput` — never on argv.
- **Every conformer must be updated:** both `CLIContainerBackend` and `MockBackend` (plus the
  `CapsuleAutomation` driver surface) or the build breaks.
- **Tests are part of the change:** delegate to the `test-author` conventions (§4.3.4). The
  required minimum: a Form-A `CLICommand` factory test; a Form-B `CLIContainerBackend` +
  `StubProcessRunner` test only when the adapter decodes/streams/maps non-zero-exit or handles a
  secret (see §4.3.4 for the exact rule).

Checklist it runs:
1. `ResourceAction` case + `verb` added.
2. `ContainerBackend` method declared.
3. `CLICommand` factory added in `CapsuleBackend`; adapter method added in `CapsuleCLIBackend` via
   `runChecked`/`OutputParser`.
4. `MockBackend` mirrors it (state mutation + `lastXxx` spy).
5. Domain model exposes it; no view code changed.
6. argv test added per the §4.3.4 rule (Form A always; Form B when the adapter decodes/streams/maps
   errors or handles a secret — secret variant asserts the secret is absent from `stub.lastCall`).
7. `make check && make test` green.

#### 4.3.2 `architecture-guardian.md` (read-only)

Frontmatter (**no Edit/Write**):
```yaml
---
name: architecture-guardian
description: >-
  Use to review a Capsule change for layering, boundary, and secret-handling
  violations before merge — e.g. "check this diff doesn't break the boundaries",
  "did I leak a secret onto argv?". Read-only reviewer: reports, never edits.
tools: Read, Grep, Glob, Bash
---
```

Body — links + operational delta:
- **Canonical rule:** the two headline layering rules live in
  [`CONTRIBUTING.md` → *Enforced boundaries*](../../CONTRIBUTING.md#enforced-boundaries-non-negotiable);
  they expand to the **eight** concrete forbidden import edges in `Scripts/check-architecture.sh`:
  UI ⊄ {`CapsuleBackend`, `CapsuleCLIBackend`, `CapsuleTerminal`}; Domain ⊄ {`CapsuleUI`,
  `CapsuleCLIBackend`, `CapsuleTerminal`}; Terminal ⊄ {`CapsuleBackend`, `CapsuleCLIBackend`}.
- `CapsuleDomain` must not use `Foundation.Process` (grep `Process\s*\(`).
- The M11 relocation facts enforced only by `ArchitectureGuardTests.swift`: `CapsuleBackend` must be
  Process-free and own `CLICommand.swift` + `ArgumentBuilder.swift`; `CapsuleCLIBackend` must
  **not** own those but must own `CLIProcessRunner.swift` (the sole `Foundation.Process` user).
- A deliberate new edge requires updating **both** `Scripts/check-architecture.sh` and
  `Tests/CapsuleUnitTests/ArchitectureGuardTests.swift`.
- Secrets: verify no password/token reaches argv (`--password-stdin` + stdin only); redaction via
  `SecretRedactor` (Diagnostics, placeholder `‹redacted›`) and `CommandRedactor` (Domain) — do not
  conflate them.
- UI localization/color rules are advisory pointers to `swiftui-view-builder`; the guardian's hard
  checks are imports, `Process`, and secrets.

Checklist it runs (read-only, reports findings — applies none):
1. `grep` touched `CapsuleUI` files for `import CapsuleBackend`/`import CapsuleCLIBackend`/`import
   CapsuleTerminal`.
2. `grep` touched `CapsuleDomain` files for `import CapsuleUI`/`import CapsuleCLIBackend`/`import
   CapsuleTerminal` and `Process(`.
3. `grep` touched `CapsuleTerminal` files for `import CapsuleBackend`/`import CapsuleCLIBackend` (so
   all eight edges are covered by the grep pass, not just by `make check`).
4. Confirm any new `CLICommand`/`ArgumentBuilder` code landed in `CapsuleBackend`, adapter code in
   `CapsuleCLIBackend`.
5. Scan for secrets on argv; confirm the stdin path is used.
6. Always run `make check`. Run `make test` **only if** `make check`/the package builds cleanly; if
   the tree does not build, report that and skip `make test` — never treat its absence as a pass.
   Suggest fixes; apply none.

#### 4.3.3 `swiftui-view-builder.md`

Frontmatter:
```yaml
---
name: swiftui-view-builder
description: >-
  Use when building or changing a CapsuleUI view, inspector, sheet, or banner —
  e.g. "add a Networks inspector tab", "build a prune confirmation sheet",
  "make this row accessible". Encodes Capsule's UI conventions.
tools: Read, Grep, Glob, Edit, Write, Bash
---
```

Body — links + operational delta (cite
[`CONTRIBUTING.md` → *Code-style rules*](../../CONTRIBUTING.md#code-style-rules) for the canonical
concurrency/layering rules; encode the concrete UI idioms below):
- **Models:** observed models are `@MainActor @Observable` (`import Observation`, **not** SwiftUI
  `ObservableObject`/`@Published`) and live in `CapsuleDomain`. Inject via `init` as `let model`
  (read-only) or `@Bindable var model` (two-way); never construct in the view, never via
  `@Environment`/`@EnvironmentObject`. Local ephemeral state = `@State private var`.
- **Boundary:** `CapsuleUI` imports only SwiftUI, `CapsuleDomain`, AppKit, Foundation, Observation,
  UniformTypeIdentifiers — **never** a Backend/Terminal module (enforced by `ArchitectureGuardTests`).
- **Localization:** every user-facing literal carries `bundle: .module`, e.g.
  `Text("Status", bundle: .module)`; proper nouns use `Text(verbatim:)`. Domain display enums get
  `.localizedTitle` accessors in `Sources/CapsuleUI/LocalizedDisplay.swift` via the `uiString(_:)`
  helper, with the default English string **byte-for-byte identical** to the Domain `title`.
- **Accessibility:** `.accessibilityLabel(Text("…", bundle: .module))`, `.accessibilityValue(…)`,
  `.accessibilityElement(children: .combine)` for composite banners, `.accessibilityHidden(true)`
  for decorative dots, `.accessibilityIdentifier(…)` for UI-test hooks. Use
  `CapsuleAccessibility.announce(_:)` for streaming/transcript VoiceOver updates. No
  `.accessibilityAddTraits(.isHeader)`; headers are structural via `Section`/`.font(.headline)`.
- **Dark mode / contrast:** no hardcoded hex palettes; derive from `CapsuleColors` semantic system
  colors. Tinted fills/borders read `@Environment(\.colorSchemeContrast)` and pass it into
  `CapsuleColors.softFill/bannerBackground/bannerBorder`.
- **Sheets:** plain structs taking closures (not models), driven from the parent via `.sheet(item:)`
  + an `Identifiable` enum; standardized chrome (`.padding(20)`, fixed `.frame(width:)`), Cancel =
  `role: .cancel` + `.keyboardShortcut(.cancelAction)`, confirm = `.borderedProminent` +
  `.keyboardShortcut(.defaultAction)`.
- **Inspectors:** `TabView` with a grouped Summary `Form` (`LabeledContent` rows) + a copyable
  monospaced Raw JSON tab that always renders the raw payload; empty/loading states use
  `ContentUnavailableView`.
- If a needed value type isn't on the domain model, stop and route the backend work to
  `command-adder` rather than importing a backend module.

Checklist it runs:
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

#### 4.3.4 `test-author.md`

Frontmatter:
```yaml
---
name: test-author
description: >-
  Use for standalone Capsule test work — adding or extending coverage on
  existing code, e.g. "cover this model's failure path", "add a golden UI
  check". Knows the unit / argv / golden-UI tiers and the mock/stub doubles.
  For tests that are part of wiring a NEW command end-to-end, use command-adder.
tools: Read, Grep, Glob, Edit, Write, Bash
---
```

Body — operational rules:
- **Three tiers, two locations.** Tiers 1+2 are SwiftPM XCTest under `Tests/CapsuleUnitTests` (run
  via `make test`/`swift test`); tier 3 golden XCUITest is `App/CapsuleUITests/CapsuleUITests.swift`
  (run via `xcodebuild`). Integration tests live in `Tests/CapsuleIntegrationTests`. Tier is chosen
  by SUT layer, not folder.
- **Tier 1 (pure logic):** plain `XCTestCase`, `@testable import CapsuleDomain`, synchronous asserts
  on return values (model after `CIDRTests.swift`).
- **Tier 2 (argv) — the required-forms rule (identical to command-adder §4.3.1):**
  - *Form A* is **always required** for a new/changed argv factory — a pure `CLICommand` factory
    test in `CLICommandTests.swift` (`import CapsuleBackend`) asserting the returned `[String]`
    exactly, e.g. `.stopContainer(id:"abc", options:.default) == ["stop","abc"]`.
    `ArgumentBuilderTests.swift` (`@testable import CapsuleBackend`) pins the primitive incl.
    flag-omitted-when-nil / option-omitted-when-disabled.
  - *Form B* is **required only when** the adapter does decoding, streaming, non-zero-exit mapping,
    or handles a secret; otherwise optional. It lives in `CLIContainerBackendTests.swift`
    (`@testable import CapsuleCLIBackend`): inject `StubProcessRunner` via the internal
    `makeBackend`/seam `init(executableURL:runner:)`, `try await` the method, assert `stub.lastCall`;
    seed `stub.result`/`stub.streamLines`/non-zero exit for decoding, streaming, and
    `BackendError.nonZeroExit` mapping; the secret variant asserts the secret is on
    `stub.lastStandardInput` and **absent** from `stub.lastCall`. Never spawns a process.
- **`MockBackend` (`Sources/CapsuleBackend/MockBackend.swift`):** in-memory `ContainerBackend`;
  instantiate directly (optionally `MockBackend(systemRunState:.stopped)`,
  `MockBackend(sampleStats:…)`), `try await` methods, assert returned data or `lastXxx` spies. It
  never builds/asserts argv. `@MainActor` model tests default a
  `model(backend: any ContainerBackend = MockBackend())` factory.
- **Tier 3 (golden UI):** `@MainActor` tests driving `XCUIApplication`; must use
  `waitForExistence(timeout:)`; `continueAfterFailure = false`. Launch mock mode with
  `app.launchEnvironment["CAPSULE_UITEST"] = "1"` (read in `CapsuleScene.init` →
  `AppEnvironment.uiTest()`), scenario via `CAPSULE_UITEST_SCENARIO`
  (`healthy`|`serviceDown`; `serviceDown` → `MockBackend(systemRunState:.stopped)`). Depend on
  seeded fixtures by exact string (container `web`, image `docker.io/library/alpine:latest`) and
  accessibility identifiers (`sidebar-containers`, `system-health-banner`, `run-sheet`, …) — do not
  change seeds/identifiers casually.
- **Coverage:** `Scripts/coverage.sh` (`make coverage`) runs only `swift test` with instrumentation;
  XCUITests are excluded.

Checklist it runs:
1. Pick the tier by SUT layer.
2. Domain logic → Tier 1; new argv → Form A (always) + Form B (only per the rule above); model
   behavior → `@MainActor` + `MockBackend` (assert data or `lastXxx`).
3. Secret path → Form B asserting `stub.lastStandardInput` set and `stub.lastCall` clean.
4. UI flow → tier-3 golden test with `CAPSULE_UITEST` + `waitForExistence`, reusing seeded
   fixtures/identifiers.
5. `make test` green (and `make coverage` if coverage is the goal).

### 4.4 Logo

- **Copy source:** `App/Assets.xcassets/AppIcon.appiconset/icon_1024.png`
- **Copy destination:** `docs/assets/capsule-logo.png` (new; create `docs/assets/`).
- **Copy is byte-for-byte** (`cp`, no re-encode). The path is not gitignored (`.gitignore` lists
  only build/dist/DS_Store/xcuserdata/etc.), so the image is committed and resolves on GitHub.
- **Exact README header replacement.** The current README begins:
  - line 1: `# Capsule`
  - line 2: blank
  - lines 3–4: the two-line subtitle — `A native macOS app for managing containers, backed by a
    command-line container` / `runtime.`
  - line 5: blank
  - line 6: `## Supported runtime envelope`

  **Replace README lines 1–5** (the `# Capsule` title, the blank, both wrapped subtitle lines, and
  the trailing blank) **with the block below followed by exactly one blank line**, so
  `## Supported runtime envelope` remains the first body heading and the tagline appears **exactly
  once**. Do **not** leave the old plaintext subtitle in place (that would render the tagline twice).

```html
<div align="center">
  <img src="docs/assets/capsule-logo.png" alt="Capsule app icon" width="128" height="128" />
  <h1>Capsule</h1>
  <p><strong>A native macOS app for managing containers, backed by a command-line container runtime.</strong></p>
</div>
```

The tagline text is copied verbatim from the current README subtitle — no invented wordmark or new
tagline.

### 4.5 `CONTRIBUTING.md` edit — "Working with AI agents" subsection

**Insertion anchor (the only valid location).** Insert a new `## Working with AI agents` H2 between
the end of the Runtime-envelope section and the `## Architecture map` heading — specifically after
the runtime-envelope bullet line ending `[README](README.md#supported-runtime-envelope).` (and its
trailing blank line) and immediately **before**:

```
## Architecture map
```

Do not add it elsewhere.

**Full proposed subsection text:**

```markdown
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
```

This subsection adds no license-header burden (Markdown is not scanned) and points at, rather than
restating, the enforced-boundary and command-recipe sections. It is count-neutral about the number
of edges (deferring to *Enforced boundaries*), so it never conflicts with the guardian's "eight
edges".

### 4.6 PR template edit

Append **one** checklist item as the **last** item of the existing `## Checklist` section in
`.github/PULL_REQUEST_TEMPLATE.md`, immediately after the final existing item (`- [ ] User-facing
strings routed through the String Catalog / \`LocalizedDisplay\`.`) and before the blank line +
`## Screenshots`. Matching the existing GitHub task-list style:

```markdown
- [ ] If AI-assisted, output was reviewed against the boundaries in CONTRIBUTING.md ("Working with AI agents") and `make check && make test` pass.
```

## 5. Non-goals (YAGNI)

- **No CI to lint agent files.** No workflow, `make` target, or script validates
  `CLAUDE.md`/`AGENTS.md`/`.claude/agents/*`. (Confirmed safe: `check-headers.sh` scans only
  `*.swift` under four roots, so root/`.claude` Markdown cannot fail `make headers`/`make
  check`/`make ci` or the pre-commit hook.)
- **No duplication.** `CLAUDE.md` links rather than restating; the subagent bodies cite the
  canonical `CONTRIBUTING.md`/`README.md` anchors for the recipe and boundary list and carry only
  the operational delta (per §4.3's anti-duplication rule) — no verbatim copies to rot.
- **No per-tool rule files** beyond `AGENTS.md` (no Cursor/Windsurf/etc. rule files).
- **No invented wordmark or new artwork** — the logo is the existing app icon; the tagline is the
  existing README subtitle.
- **No new CODEOWNERS/branch-protection changes** and **no issue-template edits.**

## 6. Verification plan

Grounded, all locally runnable:

1. **`make check` stays green.** `check = lint arch headers`. `swift-format lint` runs over
   `FORMAT_PATHS` (`Sources Tests App/Sources App/CapsuleUITests Package.swift`) — none of the new
   Markdown/PNG paths are in that set. `check-architecture.sh` greps `Sources/*` only.
   `check-headers.sh` scans `*.swift` under the four roots only. → new files cannot break `make
   check`. **Run `make check` and confirm exit 0.**
2. **`make test` stays green.** No Swift source changes; `ArchitectureGuardTests` still passes.
   **Run `make test`.**
3. **README image resolves, is committed, and the tagline is not duplicated.** Confirm
   `docs/assets/capsule-logo.png` exists, matches the source icon byte-for-byte (`cmp`), and is
   **not** gitignored (`git check-ignore docs/assets/capsule-logo.png` returns nothing; `git status`
   shows it staged). The `<img src="docs/assets/capsule-logo.png">` path renders on GitHub.
   `grep -c "A native macOS app for managing containers"` in `README.md` returns **exactly 1**, and
   there is exactly one top-level title (no leftover `# Capsule`).
4. **Agent files carry valid frontmatter.** Each `.claude/agents/*.md` begins with a `---` YAML
   block containing `name`, `description`, `tools`; `architecture-guardian`'s `tools` line is
   `Read, Grep, Glob, Bash` (no `Edit`/`Write`). Verify by reading the four files and confirming the
   four `name:` values match the roster and the guardian omits write tools.
5. **Doc edits land at the right anchors.** `CONTRIBUTING.md` shows `## Working with AI agents`
   directly above `## Architecture map`; `.github/PULL_REQUEST_TEMPLATE.md` shows the new AI
   checklist line as the last item under `## Checklist`, before `## Screenshots`; `README.md` opens
   with the centered `<div align="center">` block.
6. **Cross-links resolve.** `AGENTS.md` → `CLAUDE.md`; `CLAUDE.md` → `README.md#architecture`,
   `CONTRIBUTING.md#enforced-boundaries-non-negotiable`, `.claude/agents/`; each subagent →
   `CONTRIBUTING.md#adding-a-command-without-touching-the-ui` / `#enforced-boundaries-non-negotiable`
   / `#code-style-rules` as applicable; `CONTRIBUTING.md` "Working with AI agents" →
   `CLAUDE.md`/`AGENTS.md`/`.claude/agents/` and its in-doc recipe/boundary anchors.

## 7. File manifest

| Path | Action | Purpose | CODEOWNERS route |
| --- | --- | --- | --- |
| `CLAUDE.md` | new | Lean agent playbook linking to README/CONTRIBUTING; commands, boundaries, subagent table, read-selectively guidance. | `@capsule-maintainers` (`*`) |
| `AGENTS.md` | new | Thin pointer to `CLAUDE.md`; names the `.claude/agents` roster. | `@capsule-maintainers` (`*`) |
| `.claude/agents/command-adder.md` | new | Subagent: add a `container` command end-to-end (domain → port → `CLICommand` → adapter → `MockBackend` → argv tests). | `@capsule-maintainers` (`*`) |
| `.claude/agents/architecture-guardian.md` | new | Read-only reviewer (Read/Grep/Glob/Bash, no Edit/Write) for the eight import edges, Process ban, M11 relocation, and stdin-secret rule. | `@capsule-maintainers` (`*`) |
| `.claude/agents/swiftui-view-builder.md` | new | Subagent: CapsuleUI conventions (`@Observable` injection, `bundle: .module`, `CapsuleColors`, accessibility, sheets/inspectors). | `@capsule-maintainers` (`*`) |
| `.claude/agents/test-author.md` | new | Subagent: the three test tiers, `StubProcessRunner`/`MockBackend`, and `CAPSULE_UITEST` golden-UI mode. | `@capsule-maintainers` (`*`) |
| `docs/assets/capsule-logo.png` | new (copy) | Byte-for-byte copy of `AppIcon.appiconset/icon_1024.png` for the README header. | `@capsule-maintainers` (`*`) |
| `README.md` | edit | Replace the leading title + subtitle (lines 1–5) with the centered logo + wordmark + tagline block. | `@capsule-maintainers` (`*`) |
| `CONTRIBUTING.md` | edit | Add the `## Working with AI agents` subsection immediately before `## Architecture map`. | `@capsule-maintainers` (`*`) |
| `.github/PULL_REQUEST_TEMPLATE.md` | edit | Append one AI-assisted checklist line as the last `## Checklist` item. | `@capsule-release` |
