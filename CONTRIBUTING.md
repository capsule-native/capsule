# Contributing to Capsule

Thanks for helping build Capsule — a native macOS app for managing containers through a
command-line `container` runtime. This guide covers the architecture you’ll be working in,
the code-style rules CI enforces, and the policies for screenshots and releases.

## Runtime envelope

Capsule targets a deliberately narrow, modern envelope. Contributions must stay inside it:

- **Apple silicon only** (`arm64`), **macOS 26+**, **CLI-backed**, **unsandboxed**, **Hardened
  Runtime**, **notarized**. No Intel, no iOS, no sandboxed/App Store build. See the
  [README](README.md#supported-runtime-envelope).

## Architecture map

Capsule’s reusable core is a Swift Package of strictly-layered modules under `Sources/`. The
macOS app bundle (Info.plist, entitlements, asset catalog, UI tests) is a thin Xcode app
target under `App/`, generated from [`App/project.yml`](App/project.yml) by XcodeGen.

```
CapsuleApp         ──▶ CapsuleUI, CapsuleTerminal, CapsuleCLIBackend, CapsuleAutomation,
                       CapsuleDiagnostics, CapsuleDomain, CapsuleBackend  (+ Sparkle)
CapsuleTerminal    ──▶ CapsuleUI, CapsuleDomain, SwiftTerm   (terminal engine adapter)
CapsuleUI          ──▶ CapsuleDomain
CapsuleAutomation  ──▶ CapsuleBackend                        (leaf / side; drives the port)
CapsuleDiagnostics ──▶ CapsuleDomain, CapsuleBackend         (leaf / side)
CapsuleCLIBackend  ──▶ CapsuleBackend, CapsuleDiagnostics    (adapter; conforms to port)
CapsuleDomain      ──▶ CapsuleBackend                        (the port)
CapsuleBackend     ──▶ (no Capsule dependencies)             (port; bottom of the graph)
```

`X ──▶ Y` means “X depends on Y”. `CapsuleApp` is the **only** composition root.

| Module | Responsibility |
| --- | --- |
| `CapsuleApp` | App lifecycle, `Scene`, menu commands, window management, the Sparkle-backed updater, composition root. |
| `CapsuleDomain` | Resource models, actions, task state, outcome/diagnostics types, privacy disclosure. No UI, no `Process`. |
| `CapsuleBackend` | `ContainerBackend` protocol + shared value types (the port) + `MockBackend`. |
| `CapsuleCLIBackend` | `Process` plumbing, argument building, output parsing. Conforms to `ContainerBackend`. |
| `CapsuleAutomation` | App Intents + AppleScript vocabulary over the backend port. |
| `CapsuleDiagnostics` | `OSLog` wrappers, diagnostic-bundle export, error normalization, secret redaction. |
| `CapsuleUI` | SwiftUI views, inspectors, sheets, the updater/privacy settings surfaces. |
| `CapsuleTerminal` | SwiftTerm/PTY engine adapter. |

### Enforced boundaries (non-negotiable)

Two rules are checked automatically by
[`ArchitectureGuardTests`](Tests/CapsuleUnitTests/ArchitectureGuardTests.swift) (under
`swift test`) and [`Scripts/check-architecture.sh`](Scripts/check-architecture.sh) (pre-commit
hook + CI):

- **`CapsuleUI` never imports a Backend module** (no UI → Backend edge).
- **`CapsuleDomain` never imports `CapsuleUI`** (no Domain → UI edge) and never uses
  `Foundation.Process`.

If you introduce a new forbidden edge deliberately, update **both** the test and the script.

## Adding a command without touching the UI

The architecture is designed so a new container command is a *backend + domain* change, never
a *view* change. To add one — say, “pause a container”:

1. **Domain** — add a case to `ResourceAction` in
   [`Sources/CapsuleDomain/Action.swift`](Sources/CapsuleDomain/Action.swift): `case pause(containerID: String)`.
2. **Backend port** — declare it on `ContainerBackend`
   ([`Sources/CapsuleBackend/ContainerBackend.swift`](Sources/CapsuleBackend/ContainerBackend.swift)):
   `func pause(containerID: String) async throws`.
3. **Adapter** — implement it in
   [`Sources/CapsuleCLIBackend`](Sources/CapsuleCLIBackend) with `ArgumentBuilder` +
   `ProcessRunner` + `OutputParser`, and add an **argument-building unit test** (against the
   built argv, no real process).
4. **Mock** — mirror the behavior in
   [`Sources/CapsuleBackend/MockBackend.swift`](Sources/CapsuleBackend/MockBackend.swift) so
   the model/UI can be tested without the CLI.
5. **Domain orchestration** — expose it from the relevant model so the UI can invoke it.

Views in `CapsuleUI` bind to the domain and render whatever it exposes — they neither know nor
care which backend ran the command.

## Code-style rules

CI runs `make check` (lint + architecture + headers) and `make test`. Match what’s already
there; when in doubt, read a neighbouring file.

- **Formatting** — `swift format` via [`.swift-format`](.swift-format). Run `make format`
  before committing; CI runs `make lint --strict` and fails on any diff.
- **License headers** — every Swift file starts with the standard header. `Scripts/add-headers.sh`
  adds it to new files; `make headers` verifies.
- **Layering** — respect the dependency arrows above. No `import` that creates a forbidden
  edge. The domain maps backend value types into its own models so backend types never reach
  the UI.
- **Concurrency** — models that the UI observes are `@MainActor @Observable` (from
  `Observation`, not SwiftUI, so the domain stays UI-free). Backends are `Sendable`.
- **No force-unwrap / `try!` / `fatalError` in non-test code** for recoverable conditions;
  surface a normalized `CapsuleError` instead. Tests may force-unwrap fixtures.
- **Secrets never leak** — registry passwords and other credentials are passed via stdin, never
  argv, and are scrubbed by `SecretRedactor` before any log or diagnostic export. Never add a
  code path that echoes a password or writes command content to a shareable artifact without
  going through the `DiagnosticOptions` opt-in.
- **Tests first** — add or update tests in the same change. New pure logic gets a unit test;
  new CLI argv gets an argument-building test; new critical UI flow gets a golden UI test.

## Screenshot-update policy

Screenshots and other doc images live under [`docs/`](docs/). Because they drift silently:

- **A PR that changes visible UI must refresh any screenshot that now shows stale UI**, in the
  same PR. If you add a new surface worth documenting, add its screenshot.
- Capture on an Apple-silicon Mac at the default window size in **both light and dark mode**
  where the change is appearance-sensitive; name files `docs/screenshots/<surface>-<light|dark>.png`.
- Keep them lean (PNG, retina but cropped to the relevant surface). Reference them with
  relative Markdown links so they render on GitHub.
- If you can’t regenerate a screenshot (no Apple-silicon host), say so in the PR and a
  maintainer will capture it — don’t leave a stale image in place.

## Before you push

```sh
make check   # lint + architecture boundaries + license headers
make test    # unit tests (integration tests self-skip unless CAPSULE_INTEGRATION=1)
```

Or run everything CI runs: `make ci`. Coverage: `make coverage`.

- **Git hooks** — `make hooks` (or `make bootstrap` on a fresh clone) installs a pre-commit
  hook running the lint + header checks on staged files.
- **The app bundle** — `make app` builds the `.app` via XcodeGen + xcodebuild; `make run`
  launches it.

## Releases & versioning

- Capsule uses **semantic versioning**. The user-facing version is
  `CFBundleShortVersionString` in [`App/Info.plist`](App/Info.plist); `CFBundleVersion` is the
  monotonic build number.
- Distribution is **Developer ID + notarization + stapling** with Hardened Runtime, driven by
  [`Scripts/release/`](Scripts/release/) and `make release` (see
  [`Scripts/release/README.md`](Scripts/release/README.md)). Auto-updates ship through
  **Sparkle**; a release regenerates `appcast.xml` with the EdDSA private key.
- Tagging `vX.Y.Z` triggers [`.github/workflows/release.yml`](.github/workflows/release.yml),
  which signs, notarizes, staples, packages, and publishes the artifact + appcast.

## Reporting bugs

Open an issue with the **Bug report** template — it requires your Capsule version, `container
system version`, host macOS version, and an exported diagnostic bundle. Generate the bundle
in-app from **About / Diagnostics → Export Diagnostics…** (it is local-only and scrubbed of
secrets by default).
