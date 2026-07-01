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
