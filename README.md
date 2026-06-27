# Capsule

A native macOS app for managing containers, backed by a command-line container
runtime.

## Supported runtime envelope

Capsule targets a deliberately narrow, modern envelope:

- **Apple silicon only** (`arm64`).
- **macOS 26 or later.**
- **CLI-backed** — the app drives a `container` command-line tool via `Process`.
- **Unsandboxed**, with **Hardened Runtime** enabled.
- **Notarized** distribution.

There is no Intel, no iOS/iPadOS, and no sandboxed build. These constraints are
intentional and are encoded in the build configuration.

## Architecture

Capsule's reusable core is a Swift Package of strictly-layered modules. The macOS
app bundle (Info.plist, entitlements, asset catalog, UI tests) is a thin Xcode app
target — generated from [`App/project.yml`](App/project.yml) via XcodeGen — that
consumes those library products.

```
CapsuleApp         ──▶ CapsuleUI, CapsuleCLIBackend, CapsuleAutomation,
                       CapsuleDiagnostics, CapsuleDomain, CapsuleBackend
CapsuleUI          ──▶ CapsuleDomain
CapsuleAutomation  ──▶ CapsuleDomain                       (leaf / side)
CapsuleDiagnostics ──▶ CapsuleDomain                       (leaf / side)
CapsuleCLIBackend  ──▶ CapsuleBackend, CapsuleDiagnostics  (adapter; conforms to port)
CapsuleDomain      ──▶ CapsuleBackend                      (the port)
CapsuleBackend     ──▶ (no Capsule dependencies)           (port; bottom of the graph)
```

`X ──▶ Y` means "X depends on Y". `CapsuleApp` is the only composition root.

| Module | Responsibility |
| --- | --- |
| `CapsuleApp` | App lifecycle, top-level `Scene`, menu commands, window management, updater (Sparkle) slot, composition root. |
| `CapsuleDomain` | Resource models, actions, task state, outcome/diagnostics types. No UI, no `Process`. |
| `CapsuleBackend` | `ContainerBackend` protocol plus shared request/response value types (the port). |
| `CapsuleCLIBackend` | `Process` plumbing, argument building, output parsing. Conforms to `ContainerBackend`. |
| `CapsuleAutomation` | App Intents, AppleScript terminology, shortcut-facing models (stubs). |
| `CapsuleDiagnostics` | `OSLog` wrappers, diagnostic-bundle export, error normalization. |
| `CapsuleUI` | SwiftUI views, inspectors, sheets, terminal wrappers. |

### Enforced boundaries

Two rules are non-negotiable and are checked automatically by
[`ArchitectureGuardTests`](Tests/CapsuleUnitTests/ArchitectureGuardTests.swift)
(under `swift test`) and [`Scripts/check-architecture.sh`](Scripts/check-architecture.sh)
(in the pre-commit hook and CI):

- **`CapsuleUI` never imports a Backend module** (no UI → Backend edge).
- **`CapsuleDomain` never imports `CapsuleUI`** (no Domain → UI edge), and never uses
  `Foundation.Process`.

The composition root (`CapsuleApp/AppEnvironment`) is the single place that knows which
concrete backend is wired in. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a
command without touching any views.

## Requirements

- macOS 26+ on Apple silicon.
- **Xcode 26+** (full Xcode, not just Command Line Tools — `swift test` and the app
  target need it).
- [XcodeGen](https://github.com/yonsm/XcodeGen) for the Xcode app target:
  `brew install xcodegen`.

## Getting started

```sh
make bootstrap   # install git hooks; check tooling
make build       # build all SwiftPM modules
make test        # run unit tests (integration tests self-skip)
make app         # generate Capsule.xcodeproj and build the .app
make run         # build and launch the app
```

`make help` lists every target.

> The toolchain note: the SwiftPM modules compile with either toolchain, but XCTest
> (`swift test`) and the Xcode app target require full Xcode. The Makefile exports
> `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; override it if Xcode lives
> elsewhere.

## Tests

- **Unit tests** (`Tests/CapsuleUnitTests`) run under `swift test` and in CI. They cover
  domain models, CLI argument building, the composition root, and the architecture
  boundaries.
- **Integration tests** (`Tests/CapsuleIntegrationTests`) exercise the real `container`
  CLI. They require an Apple-silicon macOS host with the CLI installed and **self-skip
  unless `CAPSULE_INTEGRATION=1`**. They are not run in CI yet.
- **UI tests** (`App/CapsuleUITests`) are an XCUITest target run through Xcode/xcodebuild
  against the built app — not through SwiftPM.

## Distribution

`make app` produces an ad-hoc-signed app for local use. A notarized release requires a
Developer ID Application identity: build → archive → sign with `--options runtime` and
[`App/Capsule.entitlements`](App/Capsule.entitlements) → `notarytool submit` →
`stapler staple`. See `make package` for the outline. The Sparkle updater is stubbed
behind `UpdaterController` and slotted in during the distribution milestone.

## Formatting & hooks

Formatting is enforced with [`swift format`](.swift-format). `make format` rewrites in
place; `make lint` checks without modifying. `make hooks` installs a pre-commit hook that
lints staged Swift files and verifies license headers.
