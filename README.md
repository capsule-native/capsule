<div align="center">
  <img src="docs/assets/capsule-logo.png" alt="Capsule app icon" width="128" height="128" />
  <h1>Capsule</h1>
  <p><strong>A native macOS app for managing containers, backed by a command-line container runtime.</strong></p>
</div>

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
CapsuleApp         ──▶ CapsuleUI, CapsuleTerminal, CapsuleCLIBackend, CapsuleRegistryClient,
                       CapsuleAutomation, CapsuleDiagnostics, CapsuleDomain, CapsuleBackend
                       (+ Sparkle)
CapsuleTerminal    ──▶ CapsuleUI, CapsuleDomain, SwiftTerm   (terminal engine adapter)
CapsuleUI          ──▶ CapsuleDomain
CapsuleAutomation  ──▶ CapsuleBackend                        (leaf / side; drives the port)
CapsuleDiagnostics ──▶ CapsuleDomain, CapsuleBackend         (leaf / side)
CapsuleCLIBackend  ──▶ CapsuleBackend, CapsuleDiagnostics    (adapter; conforms to port)
CapsuleRegistryClient ──▶ CapsuleBackend                     (adapter; conforms to the search port)
CapsuleDomain      ──▶ CapsuleBackend                        (the port)
CapsuleBackend     ──▶ (no Capsule dependencies)             (port; bottom of the graph)
```

`X ──▶ Y` means "X depends on Y". `CapsuleApp` is the only composition root.

| Module | Responsibility |
| --- | --- |
| `CapsuleApp` | App lifecycle, top-level `Scene`, menu commands, window management, the Sparkle-backed updater, composition root. |
| `CapsuleDomain` | Resource models, actions, task state, outcome/diagnostics types, privacy disclosure. No UI, no `Process`. |
| `CapsuleBackend` | `ContainerBackend` + `ImageRegistrySearching` protocols, shared value types (the ports), `MockBackend` + `MockImageRegistry`. |
| `CapsuleCLIBackend` | `Process` plumbing, argument building, output parsing. Conforms to `ContainerBackend`. |
| `CapsuleRegistryClient` | `URLSession` adapters: unauthenticated Docker Hub search/tags (conforms to `ImageRegistrySearching`) + apple/container GitHub releases (conforms to `ContainerReleaseSource`). |
| `CapsuleAutomation` | App Intents + AppleScript vocabulary over the backend port. |
| `CapsuleDiagnostics` | `OSLog` wrappers, diagnostic-bundle export, error normalization, secret redaction. |
| `CapsuleUI` | SwiftUI views, inspectors, sheets, the updater/privacy settings surfaces. |
| `CapsuleTerminal` | SwiftTerm/PTY engine adapter. |

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
  domain models, CLI argument building, output parsing (against `MockBackend`, no real
  process), the composition root, and the architecture boundaries.
- **Golden UI tests** (`App/CapsuleUITests`) are an XCUITest target run through
  Xcode/xcodebuild. The app launches in a deterministic `MockBackend` mode
  (`CAPSULE_UITEST=1`) so critical flows — containers list, Run/Build sheets, settings,
  error states — are asserted without the real CLI. CI runs them in the `app-ui-tests` job.
- **Integration tests** (`Tests/CapsuleIntegrationTests`) exercise the real `container`
  CLI. They require an Apple-silicon macOS host with the CLI installed and **self-skip
  unless `CAPSULE_INTEGRATION=1`** — intentionally not run in CI.
- **Coverage** — `make coverage` runs the unit suite instrumented and writes
  `dist/coverage/{coverage.lcov,coverage.txt}`; CI uploads it as an artifact.

## Distribution & updates

`make app` produces an ad-hoc-signed app for local use. Releases are **Developer ID–signed,
notarized, and stapled** with the Hardened Runtime, driven by
[`Scripts/release/`](Scripts/release/):

```sh
make release       # full pipeline: archive → sign → notarize → staple → package → appcast
make release-dry   # print the whole plan without signing (no credentials needed)
```

Auto-updates ship through **[Sparkle](https://sparkle-project.org)** (integrated via SwiftPM,
unsandboxed, EdDSA-signed appcast). The updater lives behind `UpdaterController` in the UI and
is backed by `SparkleUpdaterController` in the composition root; users control it in
**Settings ▸ Updates**. Tagging `vX.Y.Z` runs
[`.github/workflows/release.yml`](.github/workflows/release.yml). See
[`Scripts/release/README.md`](Scripts/release/README.md) for the one-time key/credential setup.

## Privacy

Capsule keeps your data on your Mac: local-only diagnostic logging, opt-in (off by default)
crash submission, and **no** analytics. Secrets and command content are never collected unless
you explicitly opt in, and credentials are scrubbed even then. The full statement is in the app
under **Settings ▸ Privacy**.

## Formatting & hooks

Formatting is enforced with [`swift format`](.swift-format). `make format` rewrites in
place; `make lint` checks without modifying. `make hooks` installs a pre-commit hook that
lints staged Swift files and verifies license headers.
