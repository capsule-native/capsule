# Milestone 11 · Command palette, raw preview, presets & passthrough — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Phase-4 power-user layer — a ⌘K command palette + mirrored menu commands from one catalog; a faithful, copyable raw command preview on every sheet and every finished task (generated from the real argument builder, never an approximation); saved Run/Build presets; and a terminal passthrough (universal escape hatch + installed-plugin routes).

**Architecture:** Make the argv factory a single source of truth by relocating the pure-value `CLICommand` + `ArgumentBuilder` from `CapsuleCLIBackend` down into `CapsuleBackend` (so Domain can build the same argv the runner executes), then add the Domain value type `CommandInvocation` + a Domain-local operation-aware `CommandRedactor`. Reusable `CommandPreviewView` + `AdvancedDisclosure` consolidate the copy-pasted preview/disclosure blocks and are adopted on every sheet. Presets mirror the existing `ScopeStore` triad. The palette and menu both render one `CommandCatalog`. A `CommandConsole` + `PluginCatalogModel` provide the passthrough. All within the strict layers, enforced by `ArchitectureGuardTests`.

**Tech Stack:** Swift 6 / SwiftUI, SwiftPM package of strictly-layered modules + XcodeGen app target. Build/test via `make` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the `Makefile` exports this). **No new third-party dependency.**

## Global Constraints

- **Layering (hard rule, guarded by `Tests/CapsuleUnitTests/ArchitectureGuardTests.swift`):** `CapsuleUI` imports **only** `CapsuleDomain` (NEVER any Backend module). `CapsuleDomain` imports **only** `CapsuleBackend` (+ Foundation/Observation) — NEVER `Foundation.Process`, NEVER `CapsuleDiagnostics`/`CapsuleUI`. `CapsuleDiagnostics` depends on `CapsuleDomain`, so **Domain cannot import `SecretRedactor`** — the preview uses the new Domain-local `CommandRedactor`. `CapsuleCLIBackend` is the only `Foundation.Process` user (`CLIProcessRunner`). `CapsuleApp` is the composition root.
- **Arch-guard comment gotcha:** do NOT place the literal substrings `import CapsuleBackend` / `import CapsuleCLIBackend` / `import CapsuleUI` inside *comments* in a UI/Domain file — the guard uses a naive `source.contains(...)` scan (M9 gotcha).
- **`CommandInvocation` placement:** `CommandInvocation` + `CommandRedactor` live in **`CapsuleDomain`** (UI consumes them; UI can't see Backend). `CLICommand` + `ArgumentBuilder` move to **`CapsuleBackend`**. `CommandCatalog`/palette/console live in **`CapsuleUI`**.
- **Preview redaction:** `CommandInvocation.arguments`/`argv` are the **raw** real argv (execution + terminal). `displayString` is **redacted** via `CommandRedactor` (masks values after `--password/--passphrase/--token/--secret` and secret-keyed `-e`/`--env`/`--build-arg`; **NEVER** touches `-p`/`--publish`). All on-screen display + the copy button use `displayString`.
- **Persistence:** presets persist as Codable arrays → `UserDefaults` JSON under `capsule.runPresets` / `capsule.buildPresets`, mirroring `UserDefaultsScopeStore`. The app is **unsandboxed** (`ENABLE_APP_SANDBOX: NO`), so `BuildDraft.contextDirectory: URL?` persists as a plain path — no security-scoped bookmark.
- **Plugin discovery:** scan `/usr/local/libexec/container-plugins/` and `/usr/local/libexec/container/plugins/` for `container-*` executables; gate the surfaced entries on the system service running (`health.isRunning`).
- **Existing global keyboard shortcuts (do not collide):** ⌥⌘I (Toggle Inspector), ⌘J (Activity pane), ⇧⌘L (Log window), ⌘R (Refresh), ⌘K (now the Command Palette — enable the reserved item), ⌘, (Settings).
- **Run full `make test`** (not just `make build`) after any task that adds a domain test or touches the arch guard (the guard only runs under XCTest).
- **Every backend call routes through `ErrorNormalizer.normalize → CapsuleError`** at the domain boundary (the injected `normalize` closure).
- **Commit after each task** with a conventional-commit message; end every commit body with the two trailers: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw`.
- **License header:** every new `.swift` file starts with the standard 5-line header (`//` / `//  <Name>.swift` / `//  Capsule` / `//` / `//  Copyright © 2026 Capsule. All rights reserved.` / `//`) — the pre-commit hook enforces it.

## Ground truth (probed live 2026-07-01, `container` v1.0.0)

```
# container resolves an unknown subcommand `X` as the external plugin binary `container-X`
# under these dirs (the resolver error names them), and requires the system service running:
/usr/local/libexec/container-plugins/
/usr/local/libexec/container/plugins/
# `builder` is a built-in (not a plugin); only `builder status` is wired in Capsule today —
# reachable via the generic passthrough, NOT a dedicated route (discovery-only decision).
```

## Interface contract (cross-phase symbols — names are pinned)

- **Phase 1:** move `CLICommand`/`ArgumentBuilder` → `CapsuleBackend`; new `CommandInvocation` (Domain: `init(_ arguments:[String], executable:String="container")`, `argv`, `rawDisplay`, `displayString`); new `CommandRedactor` (Domain: `redactedArguments(_:)`, `redactedDisplay(_:)`, `placeholder`).
- **Phase 2:** `var commandInvocation: CommandInvocation` on every op model; migrated `commandPreview: String` = `commandInvocation.displayString`; `CLICommand.execShell(id:command:)`; `CommandPreviewView(_ invocation:, onEscalate:)`; `AdvancedDisclosure(_ title:, isExpanded:, content:)`; `OperationTask.invocation` + `TaskCenter.runStreaming/runAsync(invocation:)`.
- **Phase 3:** `SavedRunPreset`/`SavedBuildPreset`; `PresetStore` + `InMemoryPresetStore` (Domain) + `UserDefaultsPresetStore` (App); `RunDraft`/`BuildDraft`/`BuildPreset` `Codable`; preset methods on `RunModel`/`BuildModel`.
- **Phase 4:** `PluginInfo`, `PluginDiscovering`, `NoPluginDiscovery`, `PluginCatalogModel` (Domain); `LibexecPluginScanner` (App); `CommandConsoleView` (UI).
- **Phase 5:** `SystemTab`, `AppSheetIntent`, `ShellState.systemTab`/`.commandPalettePresented`/`.pendingSheet`; `FuzzyMatch` (Domain); `CommandShortcut`, `CommandAction`, `CommandContext`, `CommandCatalog`, `CommandPaletteView` (UI); extended `CapsuleCommands`.
- **Phase 6:** gated integration tests; final arch guard; whole-branch review + GUI smoke.

---

# Phase 1 — Foundation — relocate the argv factory + CommandInvocation + CommandRedactor

This phase makes the raw command preview a single source of truth. It relocates the pure-value `CLICommand` + `ArgumentBuilder` factory from the `CapsuleCLIBackend` adapter down into `CapsuleBackend` (no behavior change — every existing argv test stays green), then adds the Domain value type `CommandInvocation` plus a Domain-local, operation-aware `CommandRedactor` that masks secrets but **never** touches `-p`/`--publish`. The architecture guard is extended to prove the moved files are `Process`-free, now live in `CapsuleBackend`, and that `CapsuleCLIBackend` still owns the only `Foundation.Process` user.

### Task P1.1: Relocate `CLICommand` + `ArgumentBuilder` into `CapsuleBackend`

**Files:**
- Move (`git mv`): `Sources/CapsuleCLIBackend/CLICommand.swift` → `Sources/CapsuleBackend/CLICommand.swift`
- Move (`git mv`): `Sources/CapsuleCLIBackend/ArgumentBuilder.swift` → `Sources/CapsuleBackend/ArgumentBuilder.swift`
- Modify: `Sources/CapsuleBackend/CLICommand.swift:14` (delete the now-redundant `import CapsuleBackend`; keep `import Foundation`)
- Modify: `Tests/CapsuleUnitTests/ArchitectureGuardTests.swift:85-91` (extend the sanity check) + insert three new guard methods before `// MARK: - Helpers` at `:93`
- Modify: `Tests/CapsuleUnitTests/CLICommandTests.swift:13` (drop `@testable import CapsuleCLIBackend`; the file already has `import CapsuleBackend` at `:10`)
- Modify: `Tests/CapsuleUnitTests/CLICommandMachineTests.swift:10` (drop `@testable import CapsuleCLIBackend`; the file already has `@testable import CapsuleBackend` at `:9`)
- Modify: `Tests/CapsuleUnitTests/ArgumentBuilderTests.swift:10` (`@testable import CapsuleCLIBackend` → `@testable import CapsuleBackend`)
- No change needed: `Sources/CapsuleCLIBackend/CLIContainerBackend.swift` (already `import CapsuleBackend` at `:12`; `CLICommand` is `public`, so cross-module use resolves unchanged)

**Interfaces:**
- Consumes: existing `swiftFiles(inModule:)` helper in `ArchitectureGuardTests`.
- Produces: `public enum CLICommand` and `public struct ArgumentBuilder` now compiled in `CapsuleBackend` (public API byte-for-byte unchanged). New guard methods `testBackendDoesNotUseProcess()`, `testRelocatedCommandFactoryLivesInBackend()`, `testCLIBackendStillOwnsTheProcessRunner()`.

- [ ] **Step 1: Update the arch guard to assert the new location (red first).**

Extend the existing sanity check (`ArchitectureGuardTests.swift:85-91`) to also scan the backend modules:
```swift
    func testGuardActuallyFoundSources() throws {
        // Guards the guard: if path resolution breaks, the loops above would pass
        // vacuously. Make sure we are really scanning files.
        XCTAssertFalse(try swiftFiles(inModule: "CapsuleUI").isEmpty)
        XCTAssertFalse(try swiftFiles(inModule: "CapsuleDomain").isEmpty)
        XCTAssertFalse(try swiftFiles(inModule: "CapsuleTerminal").isEmpty)
        XCTAssertFalse(try swiftFiles(inModule: "CapsuleBackend").isEmpty)
        XCTAssertFalse(try swiftFiles(inModule: "CapsuleCLIBackend").isEmpty)
    }
```

Insert these three methods immediately before the `// MARK: - Helpers` line (`:93`):
```swift
    func testBackendDoesNotUseProcess() throws {
        // The relocated argv factory is pure value logic — CapsuleBackend must stay
        // Foundation.Process-free so the CLI adapter remains the only Process user.
        for file in try swiftFiles(inModule: "CapsuleBackend") {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                source.contains("Process("),
                "CapsuleBackend must not use Foundation.Process (\(file.lastPathComponent))"
            )
        }
    }

    func testRelocatedCommandFactoryLivesInBackend() throws {
        let backendNames = try swiftFiles(inModule: "CapsuleBackend").map(\.lastPathComponent)
        XCTAssertTrue(
            backendNames.contains("CLICommand.swift"),
            "CLICommand.swift must live in CapsuleBackend after the M11 relocation"
        )
        XCTAssertTrue(
            backendNames.contains("ArgumentBuilder.swift"),
            "ArgumentBuilder.swift must live in CapsuleBackend after the M11 relocation"
        )

        let adapterNames = try swiftFiles(inModule: "CapsuleCLIBackend").map(\.lastPathComponent)
        XCTAssertFalse(
            adapterNames.contains("CLICommand.swift"),
            "CLICommand.swift must no longer live in CapsuleCLIBackend"
        )
        XCTAssertFalse(
            adapterNames.contains("ArgumentBuilder.swift"),
            "ArgumentBuilder.swift must no longer live in CapsuleCLIBackend"
        )
    }

    func testCLIBackendStillOwnsTheProcessRunner() throws {
        let adapterNames = try swiftFiles(inModule: "CapsuleCLIBackend").map(\.lastPathComponent)
        XCTAssertTrue(
            adapterNames.contains("CLIProcessRunner.swift"),
            "CapsuleCLIBackend must still own CLIProcessRunner (the only Foundation.Process user)"
        )
    }
```

- [ ] **Step 2: Run it — expect FAIL.** Run `make test`. Expected: `testRelocatedCommandFactoryLivesInBackend` FAILS ("CLICommand.swift must live in CapsuleBackend…") because the files are still under `CapsuleCLIBackend`. The other new assertions (`testBackendDoesNotUseProcess`, `testCLIBackendStillOwnsTheProcessRunner`) and the rest of the suite pass.

- [ ] **Step 3: Move both files with `git mv`.**
```bash
git mv Sources/CapsuleCLIBackend/CLICommand.swift Sources/CapsuleBackend/CLICommand.swift
git mv Sources/CapsuleCLIBackend/ArgumentBuilder.swift Sources/CapsuleBackend/ArgumentBuilder.swift
```
(`ArgumentBuilder.swift` imports only `Foundation` — no content change needed.)

- [ ] **Step 4: Drop the redundant import from the moved `CLICommand.swift`.** In `Sources/CapsuleBackend/CLICommand.swift`, delete line 14 so the import block reads:
```swift
import Foundation
```
(It is now the same module as `RunConfiguration`/`BuildConfiguration`/`MachineConfiguration`/`MachineSettings`/`VolumeConfiguration`/`NetworkConfiguration`/`KernelConfiguration`/`StopOptions`, so no `import CapsuleBackend` is required; `URL` comes from `Foundation`.)

- [ ] **Step 5: Fix the three test imports.**

In `Tests/CapsuleUnitTests/CLICommandTests.swift`, delete line 13 (`@testable import CapsuleCLIBackend`). The remaining imports are:
```swift
import CapsuleBackend
import XCTest
```
In `Tests/CapsuleUnitTests/CLICommandMachineTests.swift`, delete line 10 (`@testable import CapsuleCLIBackend`). The remaining imports are:
```swift
import XCTest

@testable import CapsuleBackend
```
In `Tests/CapsuleUnitTests/ArgumentBuilderTests.swift`, change line 10 from `@testable import CapsuleCLIBackend` to:
```swift
@testable import CapsuleBackend
```

- [ ] **Step 6: Run it — expect PASS.** Run `make test`. Expected: whole suite green, including all `ArchitectureGuardTests` (the relocation assertion now passes, `CLICommandTests`/`CLICommandMachineTests`/`ArgumentBuilderTests` compile and pass against the relocated types).

- [ ] **Step 7: Commit.**
```bash
git add -A
git commit -m "refactor(backend): relocate CLICommand + ArgumentBuilder into CapsuleBackend" \
  -m "Move the pure-value argv factory from the CLI adapter into CapsuleBackend so Domain/UI can build the same raw command preview the runner executes. No behavior change; the adapter still imports it to execute. Arch guard now asserts the moved files are Process-free, live in CapsuleBackend, and that CapsuleCLIBackend still owns CLIProcessRunner." \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" \
  -m "Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw"
```

### Task P1.2: Add the operation-aware `CommandRedactor` (Domain)

**Files:**
- Create: `Sources/CapsuleDomain/CommandRedactor.swift`
- Test: `Tests/CapsuleUnitTests/CommandRedactorTests.swift`

**Interfaces:**
- Consumes: nothing (pure Swift/`Foundation`).
- Produces: `public enum CommandRedactor` with `public static let placeholder = "‹redacted›"` and `public static func redactedArguments(_ arguments: [String]) -> [String]`. (The pinned `redactedDisplay(_:)` is added in P1.3, once `CommandInvocation` exists.)

- [ ] **Step 1: Write the failing redaction test.** Create `Tests/CapsuleUnitTests/CommandRedactorTests.swift`:
```swift
//
//  CommandRedactorTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class CommandRedactorTests: XCTestCase {
    func testMasksTokenAfterSecretFlag() {
        XCTAssertEqual(
            CommandRedactor.redactedArguments(
                ["registry", "login", "--password", "hunter2", "ghcr.io"]),
            ["registry", "login", "--password", "‹redacted›", "ghcr.io"]
        )
        XCTAssertEqual(
            CommandRedactor.redactedArguments(
                ["--token", "abc", "--secret", "xyz", "--passphrase", "p"]),
            ["--token", "‹redacted›", "--secret", "‹redacted›", "--passphrase", "‹redacted›"]
        )
    }

    func testMasksEqualsFormOfSecretFlags() {
        XCTAssertEqual(
            CommandRedactor.redactedArguments(["--password=hunter2", "--token=abc"]),
            ["--password=‹redacted›", "--token=‹redacted›"]
        )
    }

    func testMasksSensitiveEnvAndBuildArgValuesByKey() {
        XCTAssertEqual(
            CommandRedactor.redactedArguments(["run", "-e", "DB_PASSWORD=s3cr3t", "img"]),
            ["run", "-e", "DB_PASSWORD=‹redacted›", "img"]
        )
        XCTAssertEqual(
            CommandRedactor.redactedArguments(
                ["--env", "API_TOKEN=t", "--build-arg", "MY_SECRET=v"]),
            ["--env", "API_TOKEN=‹redacted›", "--build-arg", "MY_SECRET=‹redacted›"]
        )
    }

    func testKeepsNonSensitiveEnvValues() {
        XCTAssertEqual(
            CommandRedactor.redactedArguments(["run", "-e", "PATH=/usr/bin", "img"]),
            ["run", "-e", "PATH=/usr/bin", "img"]
        )
    }

    func testNeverMasksPublishPorts() {
        XCTAssertEqual(
            CommandRedactor.redactedArguments(
                ["run", "-p", "8080:80", "--publish", "443:443", "img"]),
            ["run", "-p", "8080:80", "--publish", "443:443", "img"]
        )
    }

    func testLeavesTrailingSecretFlagUntouched() {
        // A secret flag with no following token: nothing to mask, no out-of-bounds.
        XCTAssertEqual(
            CommandRedactor.redactedArguments(["--password"]),
            ["--password"]
        )
    }
}
```

- [ ] **Step 2: Run it — expect FAIL.** Run `make test`. Expected: compile error in `CapsuleUnitTests` — `cannot find 'CommandRedactor' in scope`.

- [ ] **Step 3: Implement `CommandRedactor`.** Create `Sources/CapsuleDomain/CommandRedactor.swift`:
```swift
//
//  CommandRedactor.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Operation-aware redaction for command previews. Unlike SecretRedactor (which lives in
//  CapsuleDiagnostics and masks -p), this Domain-local policy NEVER masks -p/--publish, so
//  `container run -p 8080:80` previews faithfully. The real argv handed to the runner /
//  terminal is always unredacted; only the on-screen / copy form passes through here.

import Foundation

public enum CommandRedactor {
    /// Replacement token shown in place of a masked secret value.
    public static let placeholder = "‹redacted›"

    /// Flags whose immediately-following token is a bare secret to mask.
    private static let secretFlags: Set<String> =
        ["--password", "--passphrase", "--token", "--secret"]

    /// Flags whose argument is a `KEY=VALUE` entry; mask VALUE only when KEY looks sensitive.
    private static let keyValueFlags: Set<String> = ["-e", "--env", "--build-arg"]

    /// Case-insensitive KEY fragments that mark a `KEY=VALUE` entry's value as sensitive.
    private static let sensitiveKeyFragments = ["pass", "secret", "token", "key", "cred"]

    /// Returns `arguments` with secret values replaced by `placeholder`.
    ///
    /// Policy: mask the token after a secret flag and the `=value` form of those flags; mask
    /// the value portion of an `-e`/`--env`/`--build-arg` entry whose key matches a sensitive
    /// fragment. `-p`/`--publish` is never touched.
    public static func redactedArguments(_ arguments: [String]) -> [String] {
        var result: [String] = []
        result.reserveCapacity(arguments.count)
        var index = 0
        while index < arguments.count {
            let token = arguments[index]

            // `--password value` → mask the NEXT token.
            if secretFlags.contains(token), index + 1 < arguments.count {
                result.append(token)
                result.append(placeholder)
                index += 2
                continue
            }

            // `--password=value` → mask everything after the first `=`.
            if let eq = token.firstIndex(of: "="),
                secretFlags.contains(String(token[token.startIndex..<eq])) {
                result.append(String(token[token.startIndex...eq]) + placeholder)
                index += 1
                continue
            }

            // `-e KEY=secret` / `--env …` / `--build-arg …` → mask VALUE iff KEY is sensitive.
            if keyValueFlags.contains(token), index + 1 < arguments.count {
                result.append(token)
                result.append(redactedKeyValueEntry(arguments[index + 1]))
                index += 2
                continue
            }

            result.append(token)
            index += 1
        }
        return result
    }

    /// Masks the value of a `KEY=VALUE` entry when KEY matches a sensitive fragment; otherwise
    /// returns the entry unchanged (including entries that have no `=`).
    private static func redactedKeyValueEntry(_ entry: String) -> String {
        guard let eq = entry.firstIndex(of: "=") else { return entry }
        let key = entry[entry.startIndex..<eq].lowercased()
        guard sensitiveKeyFragments.contains(where: { key.contains($0) }) else { return entry }
        return String(entry[entry.startIndex...eq]) + placeholder
    }
}
```

- [ ] **Step 4: Run it — expect PASS.** Run `make test`. Expected: `CommandRedactorTests` (all 7 cases) green; `-p`/`--publish` preserved, secret flags + sensitive `KEY=VALUE` values masked; whole suite still green.

- [ ] **Step 5: Commit.**
```bash
git add -A
git commit -m "feat(domain): add operation-aware CommandRedactor (never masks -p)" \
  -m "Domain-local redactor for command previews: masks the token after --password/--passphrase/--token/--secret (and their =value form) and the value of -e/--env/--build-arg entries whose key matches pass|secret|token|key|cred, but never -p/--publish. Distinct from SecretRedactor (Diagnostics, unreachable from Domain, and its -p rule collides with publish-ports)." \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" \
  -m "Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw"
```

### Task P1.3: Add the `CommandInvocation` value type + complete `CommandRedactor`

**Files:**
- Create: `Sources/CapsuleDomain/CommandInvocation.swift`
- Modify: `Sources/CapsuleDomain/CommandRedactor.swift` (add `redactedDisplay(_:)` inside the enum, after `redactedArguments(_:)`)
- Test: `Tests/CapsuleUnitTests/CommandInvocationTests.swift`

**Interfaces:**
- Consumes: `CommandRedactor.redactedDisplay(_:)`.
- Produces:
  ```swift
  public struct CommandInvocation: Sendable, Equatable {
      public let executable: String
      public let arguments: [String]
      public init(_ arguments: [String], executable: String = "container")
      public var argv: [String]            // [executable] + arguments — RAW
      public var rawDisplay: String        // ([executable] + arguments).joined(separator: " ") — RAW
      public var displayString: String     // CommandRedactor.redactedDisplay(self) — REDACTED
  }
  ```
  and `public static func redactedDisplay(_ invocation: CommandInvocation) -> String` on `CommandRedactor`.

- [ ] **Step 1: Write the failing `CommandInvocation` test.** Create `Tests/CapsuleUnitTests/CommandInvocationTests.swift`:
```swift
//
//  CommandInvocationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class CommandInvocationTests: XCTestCase {
    func testDefaultExecutableIsContainer() {
        let inv = CommandInvocation(["image", "list", "--format", "json"])
        XCTAssertEqual(inv.executable, "container")
        XCTAssertEqual(inv.arguments, ["image", "list", "--format", "json"])
    }

    func testArgvPrependsExecutable() {
        XCTAssertEqual(CommandInvocation(["system", "df"]).argv, ["container", "system", "df"])
    }

    func testRawDisplayIsUnredactedSpaceJoined() {
        let inv = CommandInvocation(["registry", "login", "--password", "hunter2"])
        XCTAssertEqual(inv.rawDisplay, "container registry login --password hunter2")
    }

    func testDisplayStringIsRedacted() {
        let inv = CommandInvocation(["registry", "login", "--password", "hunter2", "ghcr.io"])
        XCTAssertEqual(
            inv.displayString, "container registry login --password ‹redacted› ghcr.io")
    }

    func testDisplayStringNeverRedactsPublishPorts() {
        let inv = CommandInvocation(["run", "-p", "8080:80", "alpine"])
        XCTAssertEqual(inv.displayString, "container run -p 8080:80 alpine")
    }

    func testCustomExecutableIsHonoured() {
        let inv = CommandInvocation(["--help"], executable: "container-foo")
        XCTAssertEqual(inv.argv, ["container-foo", "--help"])
        XCTAssertEqual(inv.displayString, "container-foo --help")
    }

    func testEquatable() {
        XCTAssertEqual(CommandInvocation(["a", "b"]), CommandInvocation(["a", "b"]))
        XCTAssertNotEqual(
            CommandInvocation(["a"]), CommandInvocation(["a"], executable: "other"))
    }
}
```

- [ ] **Step 2: Run it — expect FAIL.** Run `make test`. Expected: compile error in `CapsuleUnitTests` — `cannot find 'CommandInvocation' in scope` (and `CommandRedactor` has no member `redactedDisplay`).

- [ ] **Step 3: Add `redactedDisplay(_:)` to `CommandRedactor`.** In `Sources/CapsuleDomain/CommandRedactor.swift`, add this method inside the enum, immediately after `redactedArguments(_:)` (this completes `CommandRedactor` to its pinned shape):
```swift
    /// Redacted, space-joined display: `executable` + `redactedArguments(arguments)`.
    public static func redactedDisplay(_ invocation: CommandInvocation) -> String {
        ([invocation.executable] + redactedArguments(invocation.arguments))
            .joined(separator: " ")
    }
```

- [ ] **Step 4: Implement `CommandInvocation`.** Create `Sources/CapsuleDomain/CommandInvocation.swift`:
```swift
//
//  CommandInvocation.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  An executable-aware command value: the faithful argv Capsule will run (or just ran),
//  shared by every preview / console / terminal path. `argv`/`rawDisplay` are the RAW real
//  argv (execution + embedded/external terminal); `displayString` is the operation-aware
//  REDACTED form used for all on-screen display and the copy button.

import Foundation

public struct CommandInvocation: Sendable, Equatable {
    /// The executable name — "container" by default. Display only; the runner owns the URL.
    public let executable: String
    /// The faithful argv after the executable (no redaction).
    public let arguments: [String]

    public init(_ arguments: [String], executable: String = "container") {
        self.executable = executable
        self.arguments = arguments
    }

    /// Raw argv (executable first) — for execution and `TerminalRequest`.
    public var argv: [String] { [executable] + arguments }

    /// Raw, space-joined command line — NOT redacted; the Command Console / terminal seed.
    public var rawDisplay: String { ([executable] + arguments).joined(separator: " ") }

    /// Redacted, space-joined command line — every on-screen display and the copy button.
    public var displayString: String { CommandRedactor.redactedDisplay(self) }
}
```

- [ ] **Step 5: Run it — expect PASS.** Run `make test`. Expected: `CommandInvocationTests` (all 7 cases) green — `argv` prepends the executable, `rawDisplay` is unredacted, `displayString` is redacted (`--password` masked, `-p` preserved), custom executable honoured; whole suite still green.

- [ ] **Step 6: Commit.**
```bash
git add -A
git commit -m "feat(domain): add CommandInvocation value type (raw argv + redacted display)" \
  -m "Executable-aware command value shared by every preview/console/terminal path. argv/rawDisplay carry the RAW real argv for execution and terminal escalation; displayString routes through CommandRedactor for all on-screen display and the copy button. Completes CommandRedactor with redactedDisplay(_:)." \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" \
  -m "Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw"
```

# Phase 2 — Faithful preview everywhere — invocation accessors, reusable views, post-run argv

This phase makes every operation expose its exact CLI invocation as a `CommandInvocation` (built from the real argument builder relocated in Phase 1), migrates the five hand-rolled `commandPreview` strings to derive from it, and consolidates `ExecSheet`'s inline argv onto a new `CLICommand.execShell` factory. It then introduces two reusable views — `CommandPreviewView` and `AdvancedDisclosure` — and adopts them across **all** task sheets (including those that show no preview today). Finally it threads a `CommandInvocation?` onto `OperationTask` through `TaskCenter`, so the Activity transcript can show the exact command that *just ran*. Every change is redaction-correct (the preview shows `displayString`; the runner still gets raw `argv`).

---

### Task P2.1: `CLICommand.execShell` factory (the one inline-argv op consolidated)

**Files:**
- Modify: `Sources/CapsuleBackend/CLICommand.swift` (append `execShell`; the file is in `CapsuleBackend` after Phase 1's relocation)
- Test: `Tests/CapsuleUnitTests/CLICommandTests.swift` (append one test)

**Interfaces:**
- Consumes: `ArgumentBuilder` (same module).
- Produces: `public static func execShell(id: String, command: [String]) -> [String]`.

- [ ] **Step 1: Write the failing argv test.** Append to `CLICommandTests.swift`:
```swift
func testExecShellDefaultsToShAndKeepsItSingleToken() {
    XCTAssertEqual(CLICommand.execShell(id: "abc", command: []), ["exec", "-it", "abc", "sh"])
    XCTAssertEqual(
        CLICommand.execShell(id: "abc", command: ["bash", "-l"]),
        ["exec", "-it", "abc", "bash", "-l"])
}
```

- [ ] **Step 2: Run it — expect FAIL.** `make test`. Expected: compile error — `CLICommand` has no member `execShell`.

- [ ] **Step 3: Add the factory.** Append inside the `// MARK: - Containers` region of `CLICommand.swift` (next to `copy`/`listDirectory`):
```swift
/// Interactive `exec -it <id> <command>` (defaults to `sh`). The `-it` short flags stay a
/// single token to mirror the invocation users type by hand, and this is the single source
/// of truth shared by `ContainerLifecycleModel.openShell/execShell` and the Exec sheet.
public static func execShell(id: String, command: [String]) -> [String] {
    ArgumentBuilder("exec")
        .adding("-it", id)
        .adding(contentsOf: command.isEmpty ? ["sh"] : command)
        .arguments
}
```

- [ ] **Step 4: Run it — expect PASS.** `make test`. Expected: green.

- [ ] **Step 5: Commit.**
```
feat(backend): add CLICommand.execShell factory for exec -it argv

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.2: `RunModel` — `commandInvocation` + migrate `commandPreview`

**Files:**
- Modify: `Sources/CapsuleDomain/RunModel.swift:109-118` (the `commandPreview` render block)
- Test: `Tests/CapsuleUnitTests/RunModelTests.swift` (append)

**Interfaces:**
- Consumes: `CommandInvocation(_:executable:)`, `CommandInvocation.displayString` (Phase 1).
- Produces: `public var commandInvocation: CommandInvocation`; `public var commandPreview: String` (now derived).

- [ ] **Step 1: Write the failing test.** Append to `RunModelTests.swift` (the redacted env value proves the migration wired the redactor end-to-end; `-p` is preserved):
```swift
func testCommandInvocationDrivesPreviewAndRedactsSecretEnv() {
    let m = model()
    m.draft.image = "alpine"
    m.draft.envRows = ["TOKEN=secret", "FOO=bar"]
    m.draft.portRows = ["8080:80"]
    XCTAssertEqual(m.commandInvocation.rawDisplay, "container run -e TOKEN=secret -e FOO=bar -p 8080:80 alpine")
    XCTAssertEqual(m.commandPreview, "container run -e TOKEN=‹redacted› -e FOO=bar -p 8080:80 alpine")
    XCTAssertEqual(m.commandPreview, m.commandInvocation.displayString)
}

func testCommandInvocationFallsBackWhileEmpty() {
    XCTAssertEqual(model().commandInvocation.rawDisplay, "container run")
    XCTAssertEqual(model().commandPreview, "container run")
}
```

- [ ] **Step 2: Run it — expect FAIL.** `make test`. Expected: compile error — `RunModel` has no member `commandInvocation`.

- [ ] **Step 3: Migrate.** The current code is:
```swift
    public var commandPreview: String {
        switch validatedConfiguration() {
        case let .success(config):
            return (["container"] + config.arguments).joined(separator: " ")
        case .failure:
            return "container run"
        }
    }
```
Replace with:
```swift
    /// The faithful `container run …` invocation — the "Run Inspector". Falls back to
    /// `container run` while the image is empty so the field never shows a half-built command.
    public var commandInvocation: CommandInvocation {
        switch validatedConfiguration() {
        case let .success(config):
            return CommandInvocation(config.arguments)
        case .failure:
            return CommandInvocation(["run"])
        }
    }

    /// The redacted, space-joined preview string. Kept as a `String` accessor for call-site
    /// compatibility; now derives from `commandInvocation` so the preview cannot drift.
    public var commandPreview: String { commandInvocation.displayString }
```

- [ ] **Step 4: Run it — expect PASS.** `make test`. Expected: green (incl. the pre-existing `testCommandPreviewReflectsToggles` / `testCommandPreviewFallsBackWhileEmpty`).

- [ ] **Step 5: Commit.**
```
refactor(domain): derive RunModel.commandPreview from commandInvocation

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.3: `KernelManagerModel` — `commandInvocation` + migrate `commandPreview`

**Files:**
- Modify: `Sources/CapsuleDomain/KernelManagerModel.swift:114-117` (the `commandPreview` block)
- Test: `Tests/CapsuleUnitTests/KernelManagerModelTests.swift` (append)

**Interfaces:**
- Consumes: `CommandInvocation`, `KernelConfiguration.arguments`.
- Produces: `public var commandInvocation: CommandInvocation`; `public var commandPreview: String` (derived).

- [ ] **Step 1: Write the failing test.** Append to `KernelManagerModelTests.swift`:
```swift
func testCommandInvocationDrivesPreview() {
    let m = KernelManagerModel(backend: MockBackend(), taskCenter: TaskCenter())
    m.draft.mode = .recommended
    XCTAssertEqual(m.commandInvocation.rawDisplay, m.commandPreview)
    XCTAssertTrue(m.commandPreview.hasPrefix("container "))
    XCTAssertTrue(m.commandPreview.contains("--recommended"))
}
```

- [ ] **Step 2: Run it — expect FAIL.** `make test`. Expected: compile error — no member `commandInvocation`.

- [ ] **Step 3: Migrate.** The current code is:
```swift
    /// The equivalent shell command the user would type.
    public var commandPreview: String {
        "container " + configuration.arguments.joined(separator: " ")
    }
```
Replace with:
```swift
    /// The faithful kernel-set invocation the user would type.
    public var commandInvocation: CommandInvocation {
        CommandInvocation(configuration.arguments)
    }

    /// The equivalent shell command (redacted), derived from `commandInvocation`.
    public var commandPreview: String { commandInvocation.displayString }
```

- [ ] **Step 4: Run it — expect PASS.** `make test`. Expected: green.

- [ ] **Step 5: Commit.**
```
refactor(domain): derive KernelManagerModel.commandPreview from commandInvocation

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.4: `VolumeActionsModel` + `NetworkActionsModel` — `commandInvocation(for:)`, `pruneInvocation`, migrate previews

**Files:**
- Modify: `Sources/CapsuleDomain/VolumeActionsModel.swift:156-164` (the `commandPreview(for:)` block)
- Modify: `Sources/CapsuleDomain/NetworkActionsModel.swift:85-89` (the `commandPreview(for:)` block)
- Test: `Tests/CapsuleUnitTests/VolumeActionsModelTests.swift`, `Tests/CapsuleUnitTests/NetworkActionsModelTests.swift` (append)

**Interfaces:**
- Consumes: `CommandInvocation`, `CLICommand.pruneVolumes()`, `CLICommand.pruneNetworks()`, `VolumeConfiguration.arguments`, `NetworkConfiguration.arguments`.
- Produces (Volume): `func commandInvocation(for draft: VolumeDraft) -> CommandInvocation`; `func commandPreview(for draft: VolumeDraft) -> String`; `var pruneInvocation: CommandInvocation`.
- Produces (Network): `func commandInvocation(for draft: NetworkDraft) -> CommandInvocation`; `func commandPreview(for draft: NetworkDraft) -> String`; `var pruneInvocation: CommandInvocation`.

- [ ] **Step 1: Write the failing tests.** Append to `VolumeActionsModelTests.swift`:
```swift
func testVolumeCommandInvocationDropsEmptyNameAndDrivesPreview() {
    let m = VolumeActionsModel(backend: MockBackend())
    var draft = VolumeDraft()
    draft.size = "10G"
    XCTAssertFalse(m.commandInvocation(for: draft).rawDisplay.hasSuffix(" "))
    XCTAssertEqual(m.commandPreview(for: draft), m.commandInvocation(for: draft).displayString)
    XCTAssertEqual(m.pruneInvocation.rawDisplay, "container volume prune")
}
```
Append to `NetworkActionsModelTests.swift`:
```swift
func testNetworkCommandInvocationDrivesPreview() {
    let m = NetworkActionsModel(backend: MockBackend())
    var draft = NetworkDraft()
    draft.name = "app-net"
    XCTAssertEqual(m.commandPreview(for: draft), m.commandInvocation(for: draft).displayString)
    XCTAssertTrue(m.commandPreview(for: draft).hasPrefix("container network create"))
    XCTAssertEqual(m.pruneInvocation.rawDisplay, "container network prune")
}
```

- [ ] **Step 2: Run them — expect FAIL.** `make test`. Expected: compile errors — no member `commandInvocation`/`pruneInvocation`.

- [ ] **Step 3: Migrate `VolumeActionsModel`.** The current code is:
```swift
    public func commandPreview(for draft: VolumeDraft) -> String {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = configuration(from: draft, name: name)
        var argv = ["container"] + config.arguments
        // When name is empty the positional would be an empty token — drop it so the
        // preview stays clean ("container volume create --label k=v" not "…k=v ").
        if name.isEmpty { argv.removeLast() }
        return argv.joined(separator: " ")
    }
```
Replace with:
```swift
    /// The faithful `container volume create …` invocation. When the name is empty the
    /// trailing positional would be an empty token — drop it so the preview stays clean.
    public func commandInvocation(for draft: VolumeDraft) -> CommandInvocation {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var argv = configuration(from: draft, name: name).arguments
        if name.isEmpty, !argv.isEmpty { argv.removeLast() }
        return CommandInvocation(argv)
    }

    /// The redacted preview string, derived from `commandInvocation(for:)`.
    public func commandPreview(for draft: VolumeDraft) -> String {
        commandInvocation(for: draft).displayString
    }

    /// The `container volume prune` invocation, for the Clean Up sheet's preview.
    public var pruneInvocation: CommandInvocation { CommandInvocation(CLICommand.pruneVolumes()) }
```

- [ ] **Step 4: Migrate `NetworkActionsModel`.** The current code is:
```swift
    public func commandPreview(for draft: NetworkDraft) -> String {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = configuration(from: draft, name: name)
        return "container " + config.arguments.joined(separator: " ")
    }
```
Replace with:
```swift
    /// The faithful `container network create …` invocation, tolerant of empty required
    /// fields so the sheet can show it live. Keeps `NetworkConfiguration` out of the UI.
    public func commandInvocation(for draft: NetworkDraft) -> CommandInvocation {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandInvocation(configuration(from: draft, name: name).arguments)
    }

    /// The redacted preview string, derived from `commandInvocation(for:)`.
    public func commandPreview(for draft: NetworkDraft) -> String {
        commandInvocation(for: draft).displayString
    }

    /// The `container network prune` invocation, for the Clean Up sheet's preview.
    public var pruneInvocation: CommandInvocation { CommandInvocation(CLICommand.pruneNetworks()) }
```

- [ ] **Step 5: Run them — expect PASS.** `make test`. Expected: green.

- [ ] **Step 6: Commit.**
```
refactor(domain): add commandInvocation/pruneInvocation to Volume + Network models

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.5: `MachineActionsModel` — create + settings `commandInvocation`, migrate both previews

**Files:**
- Modify: `Sources/CapsuleDomain/MachineActionsModel.swift:82-84` (the create `commandPreview(for:)`)
- Modify: `Sources/CapsuleDomain/MachineActionsModel.swift:113-115` (the `settingsPreview(name:draft:)`)
- Test: `Tests/CapsuleUnitTests/MachineActionsModelCreateTests.swift`, `Tests/CapsuleUnitTests/MachineActionsModelSetTests.swift` (append)

**Interfaces:**
- Consumes: `CommandInvocation`, `MachineConfiguration.arguments`, `MachineSettings.arguments(name:)`.
- Produces: `func commandInvocation(for draft: MachineDraft) -> CommandInvocation`; `func commandPreview(for draft: MachineDraft) -> String`; `func settingsInvocation(name: String?, draft: MachineSettingsDraft) -> CommandInvocation`; `func settingsPreview(name: String?, draft: MachineSettingsDraft) -> String`.

- [ ] **Step 1: Write the failing tests.** Append to `MachineActionsModelCreateTests.swift`:
```swift
func testCreateCommandInvocationDrivesPreview() {
    let m = MachineActionsModel(backend: MockBackend())
    var draft = MachineDraft()
    draft.image = "ubuntu:24.04"
    XCTAssertEqual(m.commandPreview(for: draft), m.commandInvocation(for: draft).displayString)
    XCTAssertTrue(m.commandInvocation(for: draft).rawDisplay.hasPrefix("container machine create"))
}
```
Append to `MachineActionsModelSetTests.swift`:
```swift
func testSettingsInvocationDrivesPreview() {
    let m = MachineActionsModel(backend: MockBackend())
    var draft = MachineSettingsDraft()
    draft.cpus = "4"
    XCTAssertEqual(
        m.settingsPreview(name: "dev", draft: draft),
        m.settingsInvocation(name: "dev", draft: draft).displayString)
}
```

- [ ] **Step 2: Run them — expect FAIL.** `make test`. Expected: compile errors — no `commandInvocation`/`settingsInvocation`.

- [ ] **Step 3: Migrate the create preview.** The current code is:
```swift
    public func commandPreview(for draft: MachineDraft) -> String {
        "container " + configuration(from: draft).arguments.joined(separator: " ")
    }
```
Replace with:
```swift
    public func commandInvocation(for draft: MachineDraft) -> CommandInvocation {
        CommandInvocation(configuration(from: draft).arguments)
    }

    public func commandPreview(for draft: MachineDraft) -> String {
        commandInvocation(for: draft).displayString
    }
```

- [ ] **Step 4: Migrate the settings preview.** The current code is:
```swift
    public func settingsPreview(name: String?, draft: MachineSettingsDraft) -> String {
        "container " + settings(from: draft).arguments(name: name).joined(separator: " ")
    }
```
Replace with:
```swift
    public func settingsInvocation(name: String?, draft: MachineSettingsDraft) -> CommandInvocation {
        CommandInvocation(settings(from: draft).arguments(name: name))
    }

    public func settingsPreview(name: String?, draft: MachineSettingsDraft) -> String {
        settingsInvocation(name: name, draft: draft).displayString
    }
```

- [ ] **Step 5: Run them — expect PASS.** `make test`. Expected: green.

- [ ] **Step 6: Commit.**
```
refactor(domain): add commandInvocation/settingsInvocation to MachineActionsModel

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.6: `BuildModel` + `CopyModel` — new `commandInvocation`

**Files:**
- Modify: `Sources/CapsuleDomain/BuildModel.swift` (add `commandInvocation` after `validatedConfiguration()`)
- Modify: `Sources/CapsuleDomain/CopyModel.swift` (add `commandInvocation` after `exampleID`)
- Test: `Tests/CapsuleUnitTests/BuildModelTests.swift`, `Tests/CapsuleUnitTests/CopyModelTests.swift` (append)

**Interfaces:**
- Consumes: `CommandInvocation`, `BuildConfiguration.arguments`, `CLICommand.copy(source:destination:)`.
- Produces: `BuildModel.commandInvocation: CommandInvocation`; `CopyModel.commandInvocation: CommandInvocation`.

- [ ] **Step 1: Write the failing tests.** Append to `BuildModelTests.swift` (a secret build-arg masks; the context path is preserved):
```swift
func testBuildCommandInvocationRedactsSecretBuildArg() {
    let m = BuildModel(backend: MockBackend(), taskCenter: TaskCenter())
    m.draft.contextDirectory = URL(fileURLWithPath: "/work/app")
    m.draft.tag = "app:dev"
    m.draft.buildArgRows = ["TOKEN=abc", "MODE=ci"]
    XCTAssertEqual(
        m.commandInvocation.rawDisplay,
        "container build --tag app:dev --build-arg TOKEN=abc --build-arg MODE=ci /work/app")
    XCTAssertEqual(
        m.commandInvocation.displayString,
        "container build --tag app:dev --build-arg TOKEN=‹redacted› --build-arg MODE=ci /work/app")
}

func testBuildCommandInvocationFallsBackWhileEmpty() {
    XCTAssertEqual(
        BuildModel(backend: MockBackend(), taskCenter: TaskCenter()).commandInvocation.rawDisplay,
        "container build")
}
```
Append to `CopyModelTests.swift`:
```swift
func testCopyCommandInvocationComposesEndpoints() {
    let m = CopyModel(backend: MockBackend(), taskCenter: TaskCenter())
    m.direction = .toContainer
    m.hostURL = URL(fileURLWithPath: "/host/file.txt")
    m.containerID = "abc"
    m.containerPath = "/app/file.txt"
    XCTAssertEqual(m.commandInvocation.rawDisplay, "container copy /host/file.txt abc:/app/file.txt")
    m.direction = .fromContainer
    XCTAssertEqual(m.commandInvocation.rawDisplay, "container copy abc:/app/file.txt /host/file.txt")
}
```

- [ ] **Step 2: Run them — expect FAIL.** `make test`. Expected: compile errors — no member `commandInvocation`.

- [ ] **Step 3: Add `BuildModel.commandInvocation`.** Insert directly after the closing brace of `validatedConfiguration()` (after line 98):
```swift
    /// The faithful `container build …` invocation for the live preview; falls back to
    /// `container build` while the draft is incomplete so the field never shows a stub.
    public var commandInvocation: CommandInvocation {
        switch validatedConfiguration() {
        case let .success(config):
            return CommandInvocation(config.arguments)
        case .failure:
            return CommandInvocation(["build"])
        }
    }
```

- [ ] **Step 4: Add `CopyModel.commandInvocation`.** Insert directly after the `exampleID` computed property (after line 94):
```swift
    /// The faithful `container copy …` invocation, composing the `id:path` endpoint exactly
    /// as `CLIContainerBackend.copyTo/FromContainer` does, so the preview matches what runs.
    public var commandInvocation: CommandInvocation {
        let id = containerID.trimmingCharacters(in: .whitespaces)
        let path = containerPath.trimmingCharacters(in: .whitespaces)
        let containerEndpoint = "\(id):\(path)"
        let host = hostURL?.path ?? ""
        switch direction {
        case .toContainer:
            return CommandInvocation(CLICommand.copy(source: host, destination: containerEndpoint))
        case .fromContainer:
            return CommandInvocation(CLICommand.copy(source: containerEndpoint, destination: host))
        }
    }
```

- [ ] **Step 5: Run them — expect PASS.** `make test`. Expected: green.

- [ ] **Step 6: Commit.**
```
feat(domain): add commandInvocation to BuildModel and CopyModel

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.7: `ImageActionsModel` — per-op invocation accessors (pull/push/save/load/tag/prune)

**Files:**
- Modify: `Sources/CapsuleDomain/ImageActionsModel.swift` (add accessors after the `init`, before `// MARK: - Tag`)
- Test: `Tests/CapsuleUnitTests/ImageActionsModelTests.swift` (append)

**Interfaces:**
- Consumes: `CommandInvocation`, `CLICommand.pullImage/pushImage/saveImage/loadImage/tagImage/pruneImages`.
- Produces: `func pullInvocation(reference:platform:) -> CommandInvocation`; `func pushInvocation(reference:platform:) -> CommandInvocation`; `func saveInvocation(references:to:platform:) -> CommandInvocation`; `func loadInvocation(from:) -> CommandInvocation`; `func tagInvocation(source:target:) -> CommandInvocation`; `func pruneInvocation(all:) -> CommandInvocation`.

- [ ] **Step 1: Write the failing test.** Append to `ImageActionsModelTests.swift`:
```swift
func testImageInvocationAccessors() {
    let m = ImageActionsModel(backend: MockBackend())
    XCTAssertEqual(
        m.pullInvocation(reference: "alpine", platform: nil).rawDisplay,
        "container image pull alpine")
    XCTAssertEqual(
        m.tagInvocation(source: "a", target: "b").rawDisplay, "container image tag a b")
    XCTAssertEqual(m.pruneInvocation(all: true).rawDisplay, "container image prune --all")
    XCTAssertEqual(
        m.loadInvocation(from: URL(fileURLWithPath: "/x.tar")).rawDisplay,
        "container image load --input /x.tar")
}
```

- [ ] **Step 2: Run it — expect FAIL.** `make test`. Expected: compile errors — no such members.

- [ ] **Step 3: Add the accessors.** Insert after the `init` (after line 43, before `// MARK: - Tag`):
```swift
    // MARK: - Invocations (the exact argv each op will run)

    public func pullInvocation(reference: String, platform: String?) -> CommandInvocation {
        CommandInvocation(CLICommand.pullImage(reference: reference, platform: platform))
    }

    public func pushInvocation(reference: String, platform: String?) -> CommandInvocation {
        CommandInvocation(CLICommand.pushImage(reference: reference, platform: platform))
    }

    public func saveInvocation(references: [String], to url: URL, platform: String?)
        -> CommandInvocation
    {
        CommandInvocation(CLICommand.saveImage(references: references, to: url, platform: platform))
    }

    public func loadInvocation(from url: URL) -> CommandInvocation {
        CommandInvocation(CLICommand.loadImage(from: url))
    }

    public func tagInvocation(source: String, target: String) -> CommandInvocation {
        CommandInvocation(CLICommand.tagImage(source: source, target: target))
    }

    public func pruneInvocation(all: Bool) -> CommandInvocation {
        CommandInvocation(CLICommand.pruneImages(all: all))
    }
```

- [ ] **Step 4: Run it — expect PASS.** `make test`. Expected: green.

- [ ] **Step 5: Commit.**
```
feat(domain): add per-op CommandInvocation accessors to ImageActionsModel

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.8: `RegistriesModel.loginInvocation` + `ContainerLifecycleModel` exec/prune invocations + refactor onto `CLICommand.execShell`

**Files:**
- Modify: `Sources/CapsuleDomain/RegistriesModel.swift` (add `loginInvocation` after `login(...)`)
- Modify: `Sources/CapsuleDomain/ContainerLifecycleModel.swift:77-92` (refactor `openShell`/`execShell`) and add `execInvocation`/`pruneInvocation`
- Test: `Tests/CapsuleUnitTests/RegistriesModelTests.swift`, `Tests/CapsuleUnitTests/ContainerLifecycleModelTests.swift` (append)

**Interfaces:**
- Consumes: `CommandInvocation`, `CLICommand.registryLogin(server:username:)`, `CLICommand.execShell(id:command:)`, `CLICommand.pruneContainers()`.
- Produces: `RegistriesModel.loginInvocation(server:username:) -> CommandInvocation`; `ContainerLifecycleModel.execInvocation(id:command:) -> CommandInvocation`; `ContainerLifecycleModel.pruneInvocation: CommandInvocation`.

- [ ] **Step 1: Write the failing tests.** Append to `RegistriesModelTests.swift` (argv is already secret-free — the password is stdin-only):
```swift
func testLoginInvocationIsSecretFree() {
    let m = RegistriesModel(backend: MockBackend())
    XCTAssertEqual(
        m.loginInvocation(server: "ghcr.io", username: "me").rawDisplay,
        "container registry login --username me --password-stdin ghcr.io")
}
```
Append to `ContainerLifecycleModelTests.swift`:
```swift
func testExecInvocationDefaultsToShAndPruneInvocation() {
    let m = ContainerLifecycleModel(backend: MockBackend())
    XCTAssertEqual(m.execInvocation(id: "abc", command: []).rawDisplay, "container exec -it abc sh")
    XCTAssertEqual(
        m.execInvocation(id: "abc", command: ["bash"]).rawDisplay, "container exec -it abc bash")
    XCTAssertEqual(m.pruneInvocation.rawDisplay, "container prune")
}
```

- [ ] **Step 2: Run them — expect FAIL.** `make test`. Expected: compile errors — no such members.

- [ ] **Step 3: Add `RegistriesModel.loginInvocation`.** Insert directly after the closing brace of `login(server:username:password:)` (after line 85):
```swift
    /// The faithful `registry login` argv — it carries `--password-stdin` and the optional
    /// username but never the secret (delivered via stdin), so this is safe to show verbatim.
    public func loginInvocation(server: String, username: String?) -> CommandInvocation {
        CommandInvocation(CLICommand.registryLogin(server: server, username: username))
    }
```

- [ ] **Step 4: Refactor `ContainerLifecycleModel.openShell`/`execShell` and add accessors.** The current code is:
```swift
    public func openShell(id: String) {
        launchOrCopy(
            TerminalRequest(
                containerID: id, title: "Shell · \(id)",
                argv: ["container", "exec", "-it", id, "sh"], kind: .execShell))
    }

    /// Runs a custom command interactively (`exec -it … <command>`) in the embedded terminal,
    /// falling back to the clipboard. An empty command defaults to `sh`.
    public func execShell(id: String, command: [String]) {
        let argv = command.isEmpty ? ["sh"] : command
        launchOrCopy(
            TerminalRequest(
                containerID: id, title: "Exec · \(id)",
                argv: ["container", "exec", "-it", id] + argv, kind: .execShell))
    }
```
Replace with:
```swift
    public func openShell(id: String) {
        launchOrCopy(
            TerminalRequest(
                containerID: id, title: "Shell · \(id)",
                argv: execInvocation(id: id, command: []).argv, kind: .execShell))
    }

    /// Runs a custom command interactively (`exec -it … <command>`) in the embedded terminal,
    /// falling back to the clipboard. An empty command defaults to `sh`.
    public func execShell(id: String, command: [String]) {
        launchOrCopy(
            TerminalRequest(
                containerID: id, title: "Exec · \(id)",
                argv: execInvocation(id: id, command: command).argv, kind: .execShell))
    }

    /// The faithful `exec -it <id> <command>` invocation (defaults to `sh`) — the single
    /// source of truth shared by the shell/exec actions and the Exec sheet's preview.
    public func execInvocation(id: String, command: [String]) -> CommandInvocation {
        CommandInvocation(CLICommand.execShell(id: id, command: command))
    }

    /// The `container prune` invocation, for the Clean Up sheet's preview.
    public var pruneInvocation: CommandInvocation { CommandInvocation(CLICommand.pruneContainers()) }
```

- [ ] **Step 5: Run them — expect PASS.** `make test`. Expected: green (including the existing lifecycle shell tests, whose argv is byte-identical).

- [ ] **Step 6: Commit.**
```
refactor(domain): route exec/shell argv through CLICommand.execShell; add login/prune invocations

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.9: `CommandPreviewView` (the reusable preview block)

**Files:**
- Create: `Sources/CapsuleUI/CommandPreviewView.swift`
- Test: `Tests/CapsuleUnitTests/CommandPreviewViewTests.swift` (new)

**Interfaces:**
- Consumes: `CommandInvocation` (Domain), `CapsuleColors.activitySurface`, `Pasteboard.copy(_:)` (UI).
- Produces: `public struct CommandPreviewView: View` with `public init(_ invocation: CommandInvocation, onEscalate: ((CommandInvocation) -> Void)? = nil)`.

- [ ] **Step 1: Write the failing instantiation test.** Create `Tests/CapsuleUnitTests/CommandPreviewViewTests.swift` (compile-gate: locks the public init signatures; the FAIL is a missing symbol):
```swift
//
//  CommandPreviewViewTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import SwiftUI
import XCTest

@testable import CapsuleUI

final class CommandPreviewViewTests: XCTestCase {
    func testInitWithAndWithoutEscalation() {
        let invocation = CommandInvocation(["run", "alpine"])
        _ = CommandPreviewView(invocation)
        var escalated: CommandInvocation?
        let view = CommandPreviewView(invocation, onEscalate: { escalated = $0 })
        XCTAssertNotNil(view)
        XCTAssertNil(escalated)
    }
}
```

- [ ] **Step 2: Run it — expect FAIL.** `make test`. Expected: compile error — `CommandPreviewView` is undefined.

- [ ] **Step 3: Create the view.** Write `Sources/CapsuleUI/CommandPreviewView.swift`:
```swift
//
//  CommandPreviewView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The one "Command preview" block, shared by every task sheet and the post-run transcript.
//  Shows the redacted `displayString` monospaced + selectable, a Copy button (copies the
//  redacted string), and — when an escalation handler is supplied — an Open-in-Terminal
//  button that hands back the (raw-argv-carrying) invocation. Replaces ~5 copy-pasted blocks.
//

import CapsuleDomain
import SwiftUI

struct CommandPreviewView: View {
    private let invocation: CommandInvocation
    private let onEscalate: ((CommandInvocation) -> Void)?

    init(_ invocation: CommandInvocation, onEscalate: ((CommandInvocation) -> Void)? = nil) {
        self.invocation = invocation
        self.onEscalate = onEscalate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Command preview").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 8) {
                Text(invocation.displayString)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(CapsuleColors.activitySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(spacing: 6) {
                    Button {
                        Pasteboard.copy(invocation.displayString)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy command")
                    if let onEscalate {
                        Button {
                            onEscalate(invocation)
                        } label: {
                            Image(systemName: "terminal")
                        }
                        .buttonStyle(.borderless)
                        .help("Open in Terminal")
                    }
                }
            }
        }
    }
}
```
(Per the contract the symbol is `public` in spirit, but `CapsuleColors`/`Pasteboard` are internal to `CapsuleUI`, so the type stays module-internal and the test reaches it via `@testable import CapsuleUI`.)

- [ ] **Step 4: Run it — expect PASS.** `make test`. Expected: green.

- [ ] **Step 5: Commit.**
```
feat(ui): add reusable CommandPreviewView (preview + copy + escalate)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.10: `AdvancedDisclosure` (the reusable tiered-complexity wrapper)

**Files:**
- Create: `Sources/CapsuleUI/AdvancedDisclosure.swift`
- Test: `Tests/CapsuleUnitTests/AdvancedDisclosureTests.swift` (new)

**Interfaces:**
- Consumes: SwiftUI `DisclosureGroup`.
- Produces: `struct AdvancedDisclosure<Content: View>: View` with `init(_ title: String = "Advanced", isExpanded: Binding<Bool>? = nil, @ViewBuilder content: () -> Content)`.

- [ ] **Step 1: Write the failing instantiation test.** Create `Tests/CapsuleUnitTests/AdvancedDisclosureTests.swift`:
```swift
//
//  AdvancedDisclosureTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import SwiftUI
import XCTest

@testable import CapsuleUI

final class AdvancedDisclosureTests: XCTestCase {
    func testInitWithDefaultTitleAndExternalBinding() {
        _ = AdvancedDisclosure { Text("body") }
        let expanded = Binding<Bool>(get: { true }, set: { _ in })
        let view = AdvancedDisclosure("Advanced Options", isExpanded: expanded) { Text("body") }
        XCTAssertNotNil(view)
    }
}
```

- [ ] **Step 2: Run it — expect FAIL.** `make test`. Expected: compile error — `AdvancedDisclosure` is undefined.

- [ ] **Step 3: Create the view.** Write `Sources/CapsuleUI/AdvancedDisclosure.swift`:
```swift
//
//  AdvancedDisclosure.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The single "common controls visible / advanced flags behind disclosure" wrapper, adopted
//  across the Create/Run/Build/Copy sheets so the tiered-complexity stacking order is uniform:
//  common control → advanced disclosure → raw preview → terminal fallback. Self-manages its
//  expansion unless a caller supplies an `isExpanded` binding.
//

import SwiftUI

struct AdvancedDisclosure<Content: View>: View {
    private let title: String
    private let externalExpansion: Binding<Bool>?
    @State private var internalExpansion = false
    private let content: Content

    init(
        _ title: String = "Advanced",
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.externalExpansion = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(title, isExpanded: externalExpansion ?? $internalExpansion) {
            content
        }
    }
}
```

- [ ] **Step 4: Run it — expect PASS.** `make test`. Expected: green.

- [ ] **Step 5: Commit.**
```
feat(ui): add reusable AdvancedDisclosure tiered-complexity wrapper

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.11: Adopt the reusable views in the 5 existing-preview sheets

This is a view-only refactor: each sheet replaces its copy-pasted `VStack { Text("Command preview") … }` block with `CommandPreviewView(...)`, and the two hand-rolled `DisclosureGroup("Advanced…")` sheets switch to `AdvancedDisclosure`. The gate is `make test` (CapsuleUI compiles; the already-green `displayString` tests cover the rendered string).

**Files:**
- Modify: `Sources/CapsuleUI/QuickRunSheet.swift:68-77`
- Modify: `Sources/CapsuleUI/ExecSheet.swift:21-24, 41-50, 56-59`
- Modify: `Sources/CapsuleUI/CreateMachineSheet.swift:86-93, 110-121`
- Modify: `Sources/CapsuleUI/CreateNetworkSheet.swift:57-65, 69-78`
- Modify: `Sources/CapsuleUI/CreateVolumeSheet.swift:34-45, 47, 69-80`

**Interfaces:**
- Consumes: `CommandPreviewView(_:onEscalate:)`, `AdvancedDisclosure(_:isExpanded:content:)`, the migrated model accessors (`RunModel.commandInvocation`, `MachineActionsModel.commandInvocation(for:)`, `NetworkActionsModel.commandInvocation(for:)`, `VolumeActionsModel.commandInvocation(for:)`, `ContainerLifecycleModel.execInvocation(id:command:)`).

- [ ] **Step 1: QuickRunSheet.** Replace the current preview block:
```swift
        VStack(alignment: .leading, spacing: 4) {
            Text("Command preview").font(.caption).foregroundStyle(.secondary)
            Text(model.commandPreview)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(CapsuleColors.activitySurface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
```
with:
```swift
        CommandPreviewView(model.commandInvocation)
```

- [ ] **Step 2: ExecSheet.** Replace the inline `argv` computed property:
```swift
    private var argv: [String] {
        let tokens = CommandTokenizer.tokenize(command)
        return ["container", "exec", "-it", containerID] + (tokens.isEmpty ? ["sh"] : tokens)
    }
```
with a model-backed invocation (keeps UI free of `CLICommand`):
```swift
    private var invocation: CommandInvocation {
        lifecycle.execInvocation(id: containerID, command: CommandTokenizer.tokenize(command))
    }
```
Replace the preview block:
```swift
            VStack(alignment: .leading, spacing: 4) {
                Text("Command preview").font(.caption).foregroundStyle(.secondary)
                Text(argv.joined(separator: " "))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(CapsuleColors.activitySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
```
with:
```swift
            CommandPreviewView(invocation)
```
And update the external-terminal button body:
```swift
                Button("Open in Terminal.app") {
                    lifecycle.openInExternalTerminal(argv)
                    onClose()
                }
```
to use the raw argv off the invocation:
```swift
                Button("Open in Terminal.app") {
                    lifecycle.openInExternalTerminal(invocation.argv)
                    onClose()
                }
```

- [ ] **Step 3: CreateMachineSheet.** Replace the hand-rolled disclosure:
```swift
                DisclosureGroup("Advanced") {
                    TextField("Name (optional)", text: $draft.name)
                    Toggle("Set as default", isOn: $draft.setDefault)
                    Toggle("Create without booting", isOn: $draft.noBoot)
                    TextField("Arch", text: $draft.arch, prompt: Text("arm64"))
                    TextField("OS", text: $draft.os, prompt: Text("linux"))
                    TextField("Platform", text: $draft.platform)
                }
```
with:
```swift
                AdvancedDisclosure {
                    TextField("Name (optional)", text: $draft.name)
                    Toggle("Set as default", isOn: $draft.setDefault)
                    Toggle("Create without booting", isOn: $draft.noBoot)
                    TextField("Arch", text: $draft.arch, prompt: Text("arm64"))
                    TextField("OS", text: $draft.os, prompt: Text("linux"))
                    TextField("Platform", text: $draft.platform)
                }
```
and replace the preview block:
```swift
            VStack(alignment: .leading, spacing: 4) {
                Text("Command preview").font(.caption).foregroundStyle(.secondary)
                Text(actions.commandPreview(for: draft))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(CapsuleColors.activitySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
```
with:
```swift
            CommandPreviewView(actions.commandInvocation(for: draft))
```

- [ ] **Step 4: CreateNetworkSheet.** Replace the disclosure header:
```swift
                DisclosureGroup("Advanced Options") {
```
with:
```swift
                AdvancedDisclosure("Advanced Options") {
```
and replace the preview block:
```swift
            VStack(alignment: .leading, spacing: 4) {
                Text("Command preview").font(.caption).foregroundStyle(.secondary)
                Text(actions.commandPreview(for: draft))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(CapsuleColors.activitySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
```
with:
```swift
            CommandPreviewView(actions.commandInvocation(for: draft))
```

- [ ] **Step 5: CreateVolumeSheet.** Replace the disclosure header (it uses a bound expansion):
```swift
            DisclosureGroup("Advanced Options", isExpanded: $showAdvanced) {
```
with:
```swift
            AdvancedDisclosure("Advanced Options", isExpanded: $showAdvanced) {
```
and replace the `commandPreview` computed view:
```swift
    private var commandPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Command preview").font(.caption).foregroundStyle(.secondary)
            Text(actions.commandPreview(for: draft))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(CapsuleColors.activitySurface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
```
with:
```swift
    private var commandPreview: some View {
        CommandPreviewView(actions.commandInvocation(for: draft))
    }
```

- [ ] **Step 6: Build + verify.** `make test`. Expected: green — CapsuleUI compiles and every migrated-preview model test stays green (no behavior change beyond redaction, already asserted in P2.2/P2.4/P2.5).

- [ ] **Step 7: Commit.**
```
refactor(ui): adopt CommandPreviewView + AdvancedDisclosure in the 5 preview sheets

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.11b: Adopt `CommandPreviewView` in `MachineSettingsSheet`

`MachineSettingsSheet` carries the sixth copy-pasted `Text("Command preview")` block (the five sheets in P2.11 plus this one). Migrate it to `CommandPreviewView` over the `settingsInvocation(name:draft:)` accessor added in P2.5, so all six preview sheets share the one reusable block.

**Files:**
- Modify: `Sources/CapsuleUI/MachineSettingsSheet.swift:72-83` (the Command-preview block)

**Interfaces:**
- Consumes: `CommandPreviewView(_:)`, `MachineActionsModel.settingsInvocation(name:draft:)` (P2.5).

- [ ] **Step 1: Replace the preview block.** The current block is:
```swift
            // MARK: Command preview

            VStack(alignment: .leading, spacing: 4) {
                Text("Command preview").font(.caption).foregroundStyle(.secondary)
                Text(actions.settingsPreview(name: machine.name, draft: draft))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(CapsuleColors.activitySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
```
Replace with:
```swift
            // MARK: Command preview

            CommandPreviewView(actions.settingsInvocation(name: machine.name, draft: draft))
```

- [ ] **Step 2: Build + verify.** `make test`. Expected: green — CapsuleUI compiles; `settingsInvocation` was unit-tested in P2.5 and `settingsPreview` still derives from it, so the rendered string is unchanged (beyond redaction).

- [ ] **Step 3: Commit.**
```
refactor(ui): adopt CommandPreviewView in MachineSettingsSheet

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.12: Add a preview to the model-backed sheets that lack one (Build, Copy, prune ×4)

**Files:**
- Modify: `Sources/CapsuleUI/BuildSheet.swift:39-46` (after the Preset/No-cache row)
- Modify: `Sources/CapsuleUI/CopySheet.swift:42-46` (after the validation label) + `:106-111` (Browse disclosure → `AdvancedDisclosure`)
- Modify: `Sources/CapsuleUI/ImagePruneSheet.swift`, `Sources/CapsuleUI/PruneSheet.swift`, `Sources/CapsuleUI/NetworkPruneSheet.swift`, `Sources/CapsuleUI/VolumePruneSheet.swift` (before the button `HStack`)

**Interfaces:**
- Consumes: `CommandPreviewView(_:)`, `AdvancedDisclosure(_:isExpanded:content:)` (P2.10), `BuildModel.commandInvocation`, `CopyModel.commandInvocation`, `ImageActionsModel.pruneInvocation(all:)`, `ContainerLifecycleModel.pruneInvocation`, `NetworkActionsModel.pruneInvocation`, `VolumeActionsModel.pruneInvocation`.

- [ ] **Step 1: BuildSheet.** After the `HStack(spacing: 16) { Picker… Toggle… }` block (closes at line 46), insert:
```swift
                    CommandPreviewView(model.commandInvocation)
```

- [ ] **Step 2: CopySheet.** Directly after the validation-message `if let message = model.validationMessage { … }` block (closes at line 46), insert:
```swift
            CommandPreviewView(model.commandInvocation)
```
Then convert CopySheet's hand-rolled Browse disclosure to the reusable `AdvancedDisclosure` (P2.10), preserving its lazy-load `.onChange`. Change:
```swift
            DisclosureGroup("Browse", isExpanded: $isBrowsing) {
                browseList
            }
            .onChange(of: isBrowsing) { _, expanded in
                if expanded { Task { await reloadBrowse(path: browsePath) } }
            }
```
to:
```swift
            AdvancedDisclosure("Browse", isExpanded: $isBrowsing) {
                browseList
            }
            .onChange(of: isBrowsing) { _, expanded in
                if expanded { Task { await reloadBrowse(path: browsePath) } }
            }
```

- [ ] **Step 3: ImagePruneSheet.** Immediately before the `HStack {` that holds the Cancel/Clean Up buttons (line 75), insert:
```swift
            CommandPreviewView(actions.pruneInvocation(all: scope.isAll))
```

- [ ] **Step 4: PruneSheet.** Immediately before the button `HStack {` (line 54), insert:
```swift
            CommandPreviewView(lifecycle.pruneInvocation)
```

- [ ] **Step 5: NetworkPruneSheet.** Immediately before the button `HStack {` (line 55), insert:
```swift
            CommandPreviewView(actions.pruneInvocation)
```

- [ ] **Step 6: VolumePruneSheet.** Immediately before the button `HStack {` (line 55), insert:
```swift
            CommandPreviewView(actions.pruneInvocation)
```

- [ ] **Step 7: Build + verify.** `make test`. Expected: green (CapsuleUI compiles; the `pruneInvocation`/`commandInvocation` accessors were unit-tested in P2.4/P2.6/P2.7/P2.8).

- [ ] **Step 8: Commit.**
```
feat(ui): show command preview on Build, Copy, and all prune sheets

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.13: Add a preview to the closure-based image/registry sheets (Pull, Push, Load, Tag, RegistryLogin)

These sheets are constructed from closures, not models, so each gains an `invocationFor` provider closure and its call site (in `ImageListView` / `RegistriesView`, both of which already hold the model) supplies the matching invocation accessor.

**Files:**
- Modify: `Sources/CapsuleUI/PullImageSheet.swift` (add `invocationFor`; render in the input state)
- Modify: `Sources/CapsuleUI/PushImageSheet.swift` (same)
- Modify: `Sources/CapsuleUI/LoadImageSheet.swift` (provider over `URL`)
- Modify: `Sources/CapsuleUI/TagImageSheet.swift` (add `import CapsuleDomain` + provider over `String`)
- Modify: `Sources/CapsuleUI/RegistryLoginSheet.swift` (provider over `(String, String?)`)
- Modify: `Sources/CapsuleUI/ImageListView.swift:46-69` (pass providers)
- Modify: `Sources/CapsuleUI/RegistriesView.swift:54-62` (pass provider)

**Interfaces:**
- Consumes: `CommandPreviewView(_:)`, `ImageActionsModel.pull/push/load/tagInvocation`, `RegistriesModel.loginInvocation(server:username:)`, `CommandInvocation`.
- Produces: each sheet gains `let invocationFor: (…) -> CommandInvocation`.

- [ ] **Step 1: PullImageSheet.** Add the stored provider to the property list:
```swift
    let invocationFor: (String, String?) -> CommandInvocation
```
and replace the `init` so the injected `invocationFor` is the **last** parameter — current:
```swift
    init(
        initialReference: String = "",
        onPull: @escaping (String, String?) -> OperationTask,
        onRetry: @escaping (OperationTask) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onPull = onPull
        self.onRetry = onRetry
        self.onClose = onClose
        self._reference = State(initialValue: initialReference)
    }
```
becomes:
```swift
    init(
        initialReference: String = "",
        onPull: @escaping (String, String?) -> OperationTask,
        onRetry: @escaping (OperationTask) -> Void,
        onClose: @escaping () -> Void,
        invocationFor: @escaping (String, String?) -> CommandInvocation
    ) {
        self.onPull = onPull
        self.onRetry = onRetry
        self.onClose = onClose
        self.invocationFor = invocationFor
        self._reference = State(initialValue: initialReference)
    }
```
In the input branch, directly after the `Form { … }.formStyle(.grouped)` and before the button `HStack`, insert:
```swift
                CommandPreviewView(invocationFor(trimmedReference, platform.isEmpty ? nil : platform))
```
> **Note:** `PullImageSheet` is also constructed by Phase 5's `AppShellView.pendingSheetView` (`.pull` case, Task P5.7). That construction MUST pass the same last-parameter closure — `invocationFor: { ref, platform in imageActionsModel.pullInvocation(reference: ref, platform: platform) }` — or it will not compile against this init.

- [ ] **Step 2: PushImageSheet.** Add the stored provider to the property list:
```swift
    let invocationFor: (String, String?) -> CommandInvocation
```
and replace the `init` so `invocationFor` is the **last** parameter — current:
```swift
    init(
        initialReference: String,
        initialDigest: String,
        onPush: @escaping (String, String?) -> OperationTask,
        onRetry: @escaping (OperationTask) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.initialReference = initialReference
        self.initialDigest = initialDigest
        self.onPush = onPush
        self.onRetry = onRetry
        self.onClose = onClose
        _reference = State(initialValue: initialReference)
    }
```
becomes:
```swift
    init(
        initialReference: String,
        initialDigest: String,
        onPush: @escaping (String, String?) -> OperationTask,
        onRetry: @escaping (OperationTask) -> Void,
        onClose: @escaping () -> Void,
        invocationFor: @escaping (String, String?) -> CommandInvocation
    ) {
        self.initialReference = initialReference
        self.initialDigest = initialDigest
        self.onPush = onPush
        self.onRetry = onRetry
        self.onClose = onClose
        self.invocationFor = invocationFor
        _reference = State(initialValue: initialReference)
    }
```
In the input branch, directly after the `Form { … }.formStyle(.grouped)` and before the button `HStack`, insert:
```swift
                CommandPreviewView(invocationFor(trimmedReference, platform.isEmpty ? nil : platform))
```

- [ ] **Step 3: LoadImageSheet.** The sheet currently relies on the synthesized memberwise init; give it an explicit init so `invocationFor` can be the **last** parameter. Add the stored provider to the property list (after `onClose`):
```swift
    let invocationFor: (URL) -> CommandInvocation
```
and add the explicit init (the `@State` properties keep their in-line defaults, so they are not mentioned):
```swift
    init(
        onLoad: @escaping (URL) -> OperationTask,
        onRetry: @escaping (OperationTask) -> Void,
        onClose: @escaping () -> Void,
        invocationFor: @escaping (URL) -> CommandInvocation
    ) {
        self.onLoad = onLoad
        self.onRetry = onRetry
        self.onClose = onClose
        self.invocationFor = invocationFor
    }
```
In the input branch, directly after the existing `if let selectedURL { LabeledContent("Selected", value: selectedURL.lastPathComponent) }`, insert:
```swift
                if let selectedURL {
                    CommandPreviewView(invocationFor(selectedURL))
                }
```

- [ ] **Step 4: TagImageSheet.** Add `import CapsuleDomain` (currently only `import SwiftUI`) and a provider as the **last** stored property so the memberwise init ends with `invocationFor`. Change the property block:
```swift
    let sourceReference: String
    let sourceDigest: String
    let onTag: (String) -> Void
    let onCancel: () -> Void
```
to:
```swift
    let sourceReference: String
    let sourceDigest: String
    let onTag: (String) -> Void
    let onCancel: () -> Void
    let invocationFor: (String) -> CommandInvocation
```
(The synthesized memberwise init is now `TagImageSheet(sourceReference:sourceDigest:onTag:onCancel:invocationFor:)`.) After the `Form { … }.formStyle(.grouped)` and before the button `HStack`, insert:
```swift
            CommandPreviewView(invocationFor(trimmedTarget))
```

- [ ] **Step 5: RegistryLoginSheet.** Add a provider as the **last** stored property so the memberwise init ends with `invocationFor`. Change the property block:
```swift
    let onLogin: (String, String?, String?) async -> ErrorDetail?
    let onTest: (String, String?, String?) async -> RegistryTestResult
    let onClose: () -> Void
```
to:
```swift
    let onLogin: (String, String?, String?) async -> ErrorDetail?
    let onTest: (String, String?, String?) async -> RegistryTestResult
    let onClose: () -> Void
    let invocationFor: (String, String?) -> CommandInvocation
```
(The synthesized memberwise init is now `RegistryLoginSheet(onLogin:onTest:onClose:invocationFor:)`.) After the `Form { … }.formStyle(.grouped)`, insert — `credentials.0` is the optional username the sheet already exposes (`username.isEmpty ? nil : username`):
```swift
            CommandPreviewView(invocationFor(trimmedServer, credentials.0))
```

- [ ] **Step 6: Wire the image call sites in `ImageListView`.** Update the four constructions, each passing `invocationFor` last:
```swift
                case let .tag(reference, digest):
                    TagImageSheet(
                        sourceReference: reference, sourceDigest: digest,
                        onTag: { target in
                            activeSheet = nil
                            Task { await actions.tag(source: reference, target: target) }
                        },
                        onCancel: { activeSheet = nil },
                        invocationFor: { target in actions.tagInvocation(source: reference, target: target) })
                case let .pull(reference):
                    PullImageSheet(
                        initialReference: reference,
                        onPull: { ref, plat in actions.pull(reference: ref, platform: plat) },
                        onRetry: { actions.retryTask($0) },
                        onClose: { activeSheet = nil },
                        invocationFor: { ref, plat in actions.pullInvocation(reference: ref, platform: plat) })
                case let .push(reference, digest):
                    PushImageSheet(
                        initialReference: reference, initialDigest: digest,
                        onPush: { ref, plat in actions.push(reference: ref, platform: plat) },
                        onRetry: { actions.retryTask($0) },
                        onClose: { activeSheet = nil },
                        invocationFor: { ref, plat in actions.pushInvocation(reference: ref, platform: plat) })
                case .load:
                    LoadImageSheet(
                        onLoad: { url in actions.load(from: url) },
                        onRetry: { actions.retryTask($0) },
                        onClose: { activeSheet = nil },
                        invocationFor: { url in actions.loadInvocation(from: url) })
```

- [ ] **Step 7: Wire the registry call site in `RegistriesView`.** Update the construction, passing `invocationFor` last:
```swift
            RegistryLoginSheet(
                onLogin: { server, user, pass in
                    let ok = await model.login(server: server, username: user, password: pass)
                    return ok ? nil : model.notice?.detail
                },
                onTest: { server, user, pass in
                    await model.test(server: server, username: user, password: pass)
                },
                onClose: { showingLogin = false },
                invocationFor: { server, user in model.loginInvocation(server: server, username: user) })
```

- [ ] **Step 8: Build + verify.** `make test`. Expected: green — every provider resolves to an accessor unit-tested in P2.7/P2.8.

- [ ] **Step 9: Commit.**
```
feat(ui): show command preview on Pull/Push/Load/Tag and Registry Login sheets

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.14: `OperationTask.invocation` + thread through `TaskCenter`

**Files:**
- Modify: `Sources/CapsuleDomain/TaskCenter.swift:67-86` (add stored `invocation` + init param), `:133-146` (`runStreaming`), `:151-163` (`runAsync`), `:193-196` (`makeTask`)
- Test: `Tests/CapsuleUnitTests/TaskCenterTests.swift` (append)

**Interfaces:**
- Consumes: `CommandInvocation`.
- Produces: `OperationTask.invocation: CommandInvocation?` (init param `invocation: CommandInvocation? = nil`); `TaskCenter.runStreaming(kind:title:invocation:onSuccess:_:)` and `runAsync(kind:title:invocation:onSuccess:_:)` (new defaulted `invocation` param); `makeTask(kind:title:invocation:)`.

- [ ] **Step 1: Write the failing test.** Append to `TaskCenterTests.swift`:
```swift
func testRunStreamingThreadsInvocationOntoTask() async {
    let center = TaskCenter()
    let invocation = CommandInvocation(["image", "pull", "alpine"])
    let task = center.runStreaming(kind: .pull, title: "Pull alpine", invocation: invocation) {
        AsyncThrowingStream { $0.finish() }
    }
    XCTAssertEqual(task.invocation, invocation)
    await task.wait()
}

func testRunAsyncDefaultsInvocationToNil() async {
    let center = TaskCenter()
    let task = center.runAsync(kind: .save, title: "Save") {}
    XCTAssertNil(task.invocation)
    await task.wait()
}
```

- [ ] **Step 2: Run it — expect FAIL.** `make test`. Expected: compile error — `OperationTask` has no member `invocation`; `runStreaming` has no `invocation:` label.

- [ ] **Step 3: Add the stored property + init.** The current `OperationTask` head is:
```swift
    public let id: String
    public let title: String
    public let kind: OperationKind
    public internal(set) var state: TaskState = .running(progress: nil)
    public internal(set) var transcript: [LogLine] = []
```
Insert after `kind`:
```swift
    public let id: String
    public let title: String
    public let kind: OperationKind
    /// The exact CLI invocation this task ran (when the caller supplied it), so the transcript
    /// can render "just ran" copyably. Nil for ops that build their argv inside a closure only.
    public internal(set) var invocation: CommandInvocation?
    public internal(set) var state: TaskState = .running(progress: nil)
    public internal(set) var transcript: [LogLine] = []
```
The current init is:
```swift
    init(id: String, title: String, kind: OperationKind) {
        self.id = id
        self.title = title
        self.kind = kind
    }
```
Replace with:
```swift
    init(id: String, title: String, kind: OperationKind, invocation: CommandInvocation? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.invocation = invocation
    }
```

- [ ] **Step 4: Thread through `runStreaming`/`runAsync`/`makeTask`.** The current `runStreaming` signature is:
```swift
    public func runStreaming(
        kind: OperationKind,
        title: String,
        onSuccess: (@MainActor () async -> Void)? = nil,
        _ stream: @escaping @Sendable () -> AsyncThrowingStream<OutputLine, Error>
    ) -> OperationTask {
        let task = makeTask(kind: kind, title: title)
```
Replace its header through the `makeTask` line with:
```swift
    public func runStreaming(
        kind: OperationKind,
        title: String,
        invocation: CommandInvocation? = nil,
        onSuccess: (@MainActor () async -> Void)? = nil,
        _ stream: @escaping @Sendable () -> AsyncThrowingStream<OutputLine, Error>
    ) -> OperationTask {
        let task = makeTask(kind: kind, title: title, invocation: invocation)
```
The current `runAsync` signature is:
```swift
    public func runAsync(
        kind: OperationKind,
        title: String,
        onSuccess: (@MainActor () async -> Void)? = nil,
        _ operation: @escaping @Sendable () async throws -> Void
    ) -> OperationTask {
        let task = makeTask(kind: kind, title: title)
```
Replace its header through the `makeTask` line with:
```swift
    public func runAsync(
        kind: OperationKind,
        title: String,
        invocation: CommandInvocation? = nil,
        onSuccess: (@MainActor () async -> Void)? = nil,
        _ operation: @escaping @Sendable () async throws -> Void
    ) -> OperationTask {
        let task = makeTask(kind: kind, title: title, invocation: invocation)
```
The current `makeTask` is:
```swift
    private func makeTask(kind: OperationKind, title: String) -> OperationTask {
        counter += 1
        return OperationTask(id: "task-\(counter)", title: title, kind: kind)
    }
```
Replace with:
```swift
    private func makeTask(
        kind: OperationKind, title: String, invocation: CommandInvocation? = nil
    ) -> OperationTask {
        counter += 1
        return OperationTask(id: "task-\(counter)", title: title, kind: kind, invocation: invocation)
    }
```

- [ ] **Step 5: Run it — expect PASS.** `make test`. Expected: green — existing callers compile unchanged (the new param is defaulted and label-addressed).

- [ ] **Step 6: Commit.**
```
feat(domain): retain CommandInvocation on OperationTask via TaskCenter

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.15: Pass the invocation from every task caller

**Files:**
- Modify: `Sources/CapsuleDomain/RunModel.swift:140-162` (`runDetached`)
- Modify: `Sources/CapsuleDomain/BuildModel.swift:115-123` (`start`)
- Modify: `Sources/CapsuleDomain/ImageActionsModel.swift:140-178` (pull/push/save/load)
- Modify: `Sources/CapsuleDomain/CopyModel.swift:97-118` (`copy`)
- Modify: `Sources/CapsuleDomain/ContainerLifecycleModel.swift:377-401` (`export`)
- Modify: `Sources/CapsuleDomain/MachineActionsModel.swift:236-265` (`create`)
- Modify: `Sources/CapsuleDomain/KernelManagerModel.swift:142-152` (`install`)
- Modify: `Sources/CapsuleDomain/SystemStatusModel.swift:101-103` (`startServices`)
- Test: `Tests/CapsuleUnitTests/RunModelTests.swift`, `Tests/CapsuleUnitTests/ImageActionsModelTests.swift` (append)

**Interfaces:**
- Consumes: each model's invocation accessor + `CommandInvocation(_:)`; `CLICommand.exportContainer(id:to:)`, `CLICommand.startSystem()`.
- Produces: each task created with `invocation:` populated.

- [ ] **Step 1: Write the failing tests.** Append to `RunModelTests.swift`:
```swift
func testRunDetachedRecordsInvocationOnTask() {
    let m = model()
    m.draft.image = "alpine"
    let task = m.runDetached()
    XCTAssertEqual(task?.invocation?.rawDisplay, "container run -d alpine")
}
```
Append to `ImageActionsModelTests.swift`:
```swift
func testPullTaskCarriesInvocation() {
    let m = ImageActionsModel(backend: MockBackend())
    let task = m.pull(reference: "alpine", platform: nil)
    XCTAssertEqual(task.invocation?.rawDisplay, "container image pull alpine")
}
```

- [ ] **Step 2: Run them — expect FAIL.** `make test`. Expected: assertion failures — `task.invocation` is nil.

- [ ] **Step 3: RunModel.runDetached.** The current task creation is:
```swift
        config.detach = true
        config.interactive = false
        config.tty = false
        onActivity("Running \(config.image)…")
        let task = taskCenter.runAsync(
            kind: .run, title: "Run \(config.image)",
            onSuccess: { [reloadList] in await reloadList() }
        ) { [backend] in
            _ = try await backend.runContainer(config)
        }
```
Replace with:
```swift
        config.detach = true
        config.interactive = false
        config.tty = false
        onActivity("Running \(config.image)…")
        let task = taskCenter.runAsync(
            kind: .run, title: "Run \(config.image)",
            invocation: CommandInvocation(config.arguments),
            onSuccess: { [reloadList] in await reloadList() }
        ) { [backend] in
            _ = try await backend.runContainer(config)
        }
```

- [ ] **Step 4: BuildModel.start.** The current body is:
```swift
    private func start(_ config: BuildConfiguration) -> OperationTask {
        onActivity("Building \(config.tag)…")
        return taskCenter.runStreaming(
            kind: .build, title: "Build \(config.tag)",
            onSuccess: { [reloadList] in await reloadList() }
        ) { [backend] in
            backend.buildImage(config)
        }
    }
```
Replace with:
```swift
    private func start(_ config: BuildConfiguration) -> OperationTask {
        onActivity("Building \(config.tag)…")
        return taskCenter.runStreaming(
            kind: .build, title: "Build \(config.tag)",
            invocation: CommandInvocation(config.arguments),
            onSuccess: { [reloadList] in await reloadList() }
        ) { [backend] in
            backend.buildImage(config)
        }
    }
```

- [ ] **Step 5: ImageActionsModel pull/push/save/load.** Update each `taskCenter` call to pass `invocation:`. Pull:
```swift
        return taskCenter.runStreaming(
            kind: .pull, title: "Pull \(reference)",
            invocation: pullInvocation(reference: reference, platform: platform),
            onSuccess: { [reloadList] in await reloadList() }
        ) { [backend] in
            backend.pullImage(reference: reference, platform: platform)
        }
```
Push:
```swift
        return taskCenter.runStreaming(
            kind: .push, title: "Push \(reference)",
            invocation: pushInvocation(reference: reference, platform: platform)
        ) { [backend] in
            backend.pushImage(reference: reference, platform: platform)
        }
```
Save:
```swift
        taskCenter.runAsync(
            kind: .save, title: "Save \(references.joined(separator: ", "))",
            invocation: saveInvocation(references: references, to: url, platform: platform)
        ) { [backend] in
            try await backend.saveImage(references: references, to: url, platform: platform)
        }
```
Load:
```swift
        taskCenter.runAsync(
            kind: .load, title: "Load \(url.lastPathComponent)",
            invocation: loadInvocation(from: url),
            onSuccess: { [reloadList] in await reloadList() }
        ) { [backend] in
            try await backend.loadImage(from: url)
        }
```

- [ ] **Step 6: CopyModel.copy.** The current task creation is:
```swift
        onActivity(title)
        return taskCenter.runAsync(kind: .copy, title: title) { [backend] in
```
Replace the `runAsync` head with (capture the invocation before the closure):
```swift
        onActivity(title)
        return taskCenter.runAsync(kind: .copy, title: title, invocation: commandInvocation) {
            [backend] in
```

- [ ] **Step 7: ContainerLifecycleModel.export.** The current task creation is:
```swift
        busy.insert(id)
        let task = taskCenter.runAsync(kind: .export, title: "Export \(id)") {
            [backend] in try await backend.exportContainer(id: id, to: url)
        }
```
Replace with:
```swift
        busy.insert(id)
        let task = taskCenter.runAsync(
            kind: .export, title: "Export \(id)",
            invocation: CommandInvocation(CLICommand.exportContainer(id: id, to: url))
        ) { [backend] in try await backend.exportContainer(id: id, to: url) }
```

- [ ] **Step 8: MachineActionsModel.create.** The current task creation is:
```swift
        if let taskCenter {
            taskCenter.runStreaming(
                kind: .machineCreate, title: "Create machine \(name)",
                onSuccess: { [weak self] in
```
Replace the `runStreaming` head with:
```swift
        if let taskCenter {
            taskCenter.runStreaming(
                kind: .machineCreate, title: "Create machine \(name)",
                invocation: CommandInvocation(config.arguments),
                onSuccess: { [weak self] in
```

- [ ] **Step 9: KernelManagerModel.install.** The current task creation is:
```swift
        taskCenter.runStreaming(
            kind: .systemKernelInstall,
            title: "Install Kernel",
            onSuccess: { [weak self] in await self?.loadCurrent() }
        ) { [backend] in
            backend.setKernel(config)
        }
```
Replace with:
```swift
        taskCenter.runStreaming(
            kind: .systemKernelInstall,
            title: "Install Kernel",
            invocation: CommandInvocation(config.arguments),
            onSuccess: { [weak self] in await self?.loadCurrent() }
        ) { [backend] in
            backend.setKernel(config)
        }
```

- [ ] **Step 10: SystemStatusModel.startServices.** The current task creation is:
```swift
        let task = taskCenter.runAsync(kind: .systemStart, title: "Start container services") {
            [backend] in try await backend.startSystem()
        }
```
Replace with:
```swift
        let task = taskCenter.runAsync(
            kind: .systemStart, title: "Start container services",
            invocation: CommandInvocation(CLICommand.startSystem())
        ) { [backend] in try await backend.startSystem() }
```

- [ ] **Step 11: Run all — expect PASS.** `make test`. Expected: green (run the full suite — multiple domain models touched).

- [ ] **Step 12: Commit.**
```
feat(domain): pass the CommandInvocation from every task caller into TaskCenter

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P2.16: `TaskTranscriptView` renders the post-run invocation

**Files:**
- Modify: `Sources/CapsuleUI/TaskTranscriptView.swift:14-17` (add the `onEscalate` handler) and `:19-41` (insert the preview after the header `HStack`)
- Modify: `Sources/CapsuleUI/ActivityPaneView.swift:207-211` (wire `onEscalate` on the Tasks-tab rows to open the embedded terminal)

**Interfaces:**
- Consumes: `OperationTask.invocation`, `CommandPreviewView(_:onEscalate:)`, `TerminalRequest(containerID:title:argv:kind:)`, `ShellState.openTerminal(_:)`.
- Produces: the "just ran" command shown copyably below the task title when `task.invocation != nil`; an "Open in Terminal" escalation reachable on the Activity pane's finished-task rows (other call sites pass no handler, so they stay Copy-only).

- [ ] **Step 1: Add the `onEscalate` handler to `TaskTranscriptView`.** It sits alongside the existing optional handlers and defaults to nil (via the synthesized memberwise init), so the sheet call sites that pass only `task`/`onRetry`/`onCancel` keep compiling. Change the property block:
```swift
struct TaskTranscriptView: View {
    let task: OperationTask
    var onRetry: (() -> Void)?
    var onCancel: (() -> Void)?
```
to:
```swift
struct TaskTranscriptView: View {
    let task: OperationTask
    var onRetry: (() -> Void)?
    var onCancel: (() -> Void)?
    var onEscalate: ((CommandInvocation) -> Void)?
```

- [ ] **Step 2: Insert the preview (with escalation).** The current `body` opens:
```swift
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                stateIcon
                Text(task.title).font(.callout.weight(.medium))
                Spacer()
                if task.transcript.isEmpty == false {
                    Button {
                        Pasteboard.copy(task.transcriptText)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy transcript")
                }
                if task.state.isActive, task.isCancellable, let onCancel {
                    Button("Stop", role: .destructive, action: onCancel)
                        .controlSize(.small)
                }
                if isRetryable, let onRetry {
                    Button("Retry", action: onRetry)
                }
            }

            if let progress = determinateProgress {
```
Insert the invocation block between the closing `}` of the header `HStack` and the `if let progress` line, passing `onEscalate` through so the preview offers "Open in Terminal" only when a handler is wired:
```swift
                if isRetryable, let onRetry {
                    Button("Retry", action: onRetry)
                }
            }

            if let invocation = task.invocation {
                CommandPreviewView(invocation, onEscalate: onEscalate)
            }

            if let progress = determinateProgress {
```

- [ ] **Step 3: Wire escalation at the Activity-pane task list.** In `Sources/CapsuleUI/ActivityPaneView.swift`, the Tasks tab builds each row with `TaskTranscriptView(task:onRetry:onCancel:)`. Add an `onEscalate` that re-runs the exact command in the embedded terminal (`ActivityPaneView` already `import`s `CapsuleDomain` and holds `@Bindable var shell: ShellState`). Change:
```swift
                            TaskTranscriptView(
                                task: task,
                                onRetry: { taskCenter?.retry(task) },
                                onCancel: { taskCenter?.cancel(task) })
```
to:
```swift
                            TaskTranscriptView(
                                task: task,
                                onRetry: { taskCenter?.retry(task) },
                                onCancel: { taskCenter?.cancel(task) },
                                onEscalate: { invocation in
                                    shell.openTerminal(
                                        TerminalRequest(
                                            containerID: nil,
                                            title: invocation.rawDisplay,
                                            argv: invocation.argv,
                                            kind: .runInteractive))
                                })
```
The other `TaskTranscriptView` call sites — the transfer sheets (`PullImageSheet`/`PushImageSheet`/`LoadImageSheet`), `RunFailureTriageView`, `QuickRunSheet`, `BuildSheet`, `CopySheet` — pass no `onEscalate`, so their previews show Copy only.

- [ ] **Step 4: Build + verify.** `make test`. Expected: green — CapsuleUI compiles; the Activity pane's finished-task rows now render the exact `task.invocation` with an Open-in-Terminal escalation, while sheet transcripts stay Copy-only.

- [ ] **Step 5: Commit.**
```
feat(ui): render a task's exact command + reachable terminal escalation on finished tasks

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

# Phase 3 — Saved Run/Build presets

This phase makes a configured Quick Run or Build re-usable: the user saves the current sheet as a named preset, re-applies it pre-filled, and deletes it — mirroring the existing "Save Scope" precedent (`ContainerScope` + `ScopeStore` triad + `UserDefaultsScopeStore`). We first make `RunDraft`/`BuildDraft`/`BuildPreset` `Codable` (the only non-primitive is `BuildDraft.contextDirectory: URL?`, persisted as a plain path since the app is unsandboxed), then add the `SavedRunPreset`/`SavedBuildPreset` value types + `PresetStore` seam + `InMemoryPresetStore` double in `CapsuleDomain` and the `UserDefaultsPresetStore` concrete in `CapsuleApp`, add load/save/delete/apply methods to `RunModel`/`BuildModel`, surface a Save-as-preset alert + apply/delete menu in both sheets, and inject the real store in the composition root.

---

### Task P3.1: `Codable` drafts (`RunDraft`, `BuildDraft`, `BuildPreset`)

**Files:**
- Modify: `Sources/CapsuleDomain/RunModel.swift:17` (`RunDraft` decl — add `Codable`)
- Modify: `Sources/CapsuleDomain/BuildModel.swift:17` (`BuildPreset` enum decl — add `Codable`), `:34-44` (add custom `Codable` extension for `BuildDraft`)
- Test: Create `Tests/CapsuleUnitTests/DraftCodableTests.swift`

**Interfaces:**
- Consumes: `RunDraft` (existing `Sendable, Equatable`), `BuildDraft` (existing `Sendable, Equatable`, `contextDirectory: URL?`), `BuildPreset: String` enum.
- Produces: `RunDraft: Codable` (synthesized); `BuildPreset: Codable` (raw-value synthesized); `extension BuildDraft: Codable` with custom `CodingKeys` mapping `contextDirectory: URL?` ↔ optional path `String` (`encode(contextDirectory?.path)`, `decode → URL(fileURLWithPath:)`).

- [ ] **Step 1: Write the failing round-trip test.** Create `Tests/CapsuleUnitTests/DraftCodableTests.swift`:
```swift
//
//  DraftCodableTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class DraftCodableTests: XCTestCase {
    func testRunDraftRoundTrips() throws {
        var draft = RunDraft(image: "alpine:latest")
        draft.name = "web"
        draft.command = "sh -c 'echo hi'"
        draft.envRows = ["KEY=value"]
        draft.portRows = ["8080:80"]
        draft.volumeRows = ["/host:/container"]
        draft.interactive = true
        draft.remove = true
        draft.detach = true
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(RunDraft.self, from: data)
        XCTAssertEqual(decoded, draft)
    }

    func testBuildDraftEncodesContextDirectoryAsPlainPath() throws {
        var draft = BuildDraft()
        draft.contextDirectory = URL(fileURLWithPath: "/tmp/project")
        draft.tag = "app:dev"
        draft.dockerfile = "Dockerfile.web"
        draft.buildArgRows = ["KEY=value"]
        draft.noCache = true
        draft.preset = .plainProgress
        let data = try JSONEncoder().encode(draft)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        // A plain path string, NOT the synthesized URL keyed container.
        XCTAssertFalse(json.contains("\"relative\""))
        let decoded = try JSONDecoder().decode(BuildDraft.self, from: data)
        XCTAssertEqual(decoded, draft)
        XCTAssertEqual(decoded.contextDirectory?.path, "/tmp/project")
    }

    func testBuildDraftRoundTripsNilContext() throws {
        let draft = BuildDraft()
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(BuildDraft.self, from: data)
        XCTAssertNil(decoded.contextDirectory)
        XCTAssertEqual(decoded, draft)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `make test`. Expected: compile error (`RunDraft`/`BuildDraft` do not conform to `Codable`).

- [ ] **Step 3: Add `Codable` to `RunDraft`.** In `Sources/CapsuleDomain/RunModel.swift`, change the struct declaration (currently `public struct RunDraft: Sendable, Equatable {`) to:
```swift
public struct RunDraft: Sendable, Equatable, Codable {
```

- [ ] **Step 4: Add `Codable` to `BuildPreset`.** In `Sources/CapsuleDomain/BuildModel.swift`, change the enum declaration (currently `public enum BuildPreset: String, Sendable, CaseIterable, Identifiable {`) to:
```swift
public enum BuildPreset: String, Sendable, Codable, CaseIterable, Identifiable {
```

- [ ] **Step 5: Add the custom `Codable` extension for `BuildDraft`.** Leave the `BuildDraft` struct declaration (`public struct BuildDraft: Sendable, Equatable {`) unchanged and append this extension immediately after the struct's closing brace (after line 44) in `Sources/CapsuleDomain/BuildModel.swift`:
```swift
extension BuildDraft: Codable {
    private enum CodingKeys: String, CodingKey {
        case contextDirectory, tag, dockerfile, buildArgRows, noCache, preset
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        // The app is unsandboxed, so the context folder persists as a plain path
        // (no security-scoped bookmark) rather than the synthesized URL container.
        if let path = try container.decodeIfPresent(String.self, forKey: .contextDirectory) {
            self.contextDirectory = URL(fileURLWithPath: path)
        }
        self.tag = try container.decode(String.self, forKey: .tag)
        self.dockerfile = try container.decode(String.self, forKey: .dockerfile)
        self.buildArgRows = try container.decode([String].self, forKey: .buildArgRows)
        self.noCache = try container.decode(Bool.self, forKey: .noCache)
        self.preset = try container.decode(BuildPreset.self, forKey: .preset)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(contextDirectory?.path, forKey: .contextDirectory)
        try container.encode(tag, forKey: .tag)
        try container.encode(dockerfile, forKey: .dockerfile)
        try container.encode(buildArgRows, forKey: .buildArgRows)
        try container.encode(noCache, forKey: .noCache)
        try container.encode(preset, forKey: .preset)
    }
}
```

- [ ] **Step 6: Run — expect PASS.** `make test`. Expected: the three new tests pass; whole suite green.

- [ ] **Step 7: Commit.**
```
feat(presets): make RunDraft/BuildDraft/BuildPreset Codable

RunDraft + BuildPreset get synthesized Codable; BuildDraft gets a custom
extension that persists contextDirectory as a plain path (unsandboxed app,
no bookmark). Foundation for saved Run/Build presets.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P3.2: `SavedRunPreset`/`SavedBuildPreset` + `PresetStore` triad (Domain)

**Files:**
- Create: `Sources/CapsuleDomain/Presets.swift`
- Test: Create `Tests/CapsuleUnitTests/PresetStoreTests.swift`

**Interfaces:**
- Consumes: `RunDraft`/`BuildDraft` (now `Codable, Equatable, Sendable` from P3.1).
- Produces: `SavedRunPreset { id: UUID; name: String; draft: RunDraft }` and `SavedBuildPreset { id: UUID; name: String; draft: BuildDraft }` (both `Codable, Identifiable, Equatable, Sendable`); `protocol PresetStore: Sendable { loadRunPresets() -> [SavedRunPreset]; saveRunPresets(_:); loadBuildPresets() -> [SavedBuildPreset]; saveBuildPresets(_:) }`; `final class InMemoryPresetStore: PresetStore, @unchecked Sendable`.

- [ ] **Step 1: Write the failing round-trip test.** Create `Tests/CapsuleUnitTests/PresetStoreTests.swift`:
```swift
//
//  PresetStoreTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class PresetStoreTests: XCTestCase {
    func testInMemoryRunPresetsRoundTrip() {
        let store = InMemoryPresetStore()
        XCTAssertTrue(store.loadRunPresets().isEmpty)
        let presets = [SavedRunPreset(name: "Web", draft: RunDraft(image: "nginx"))]
        store.saveRunPresets(presets)
        XCTAssertEqual(store.loadRunPresets(), presets)
    }

    func testInMemoryBuildPresetsRoundTrip() {
        let store = InMemoryPresetStore()
        XCTAssertTrue(store.loadBuildPresets().isEmpty)
        var draft = BuildDraft()
        draft.tag = "app:dev"
        let presets = [SavedBuildPreset(name: "App", draft: draft)]
        store.saveBuildPresets(presets)
        XCTAssertEqual(store.loadBuildPresets(), presets)
    }

    func testInMemorySeedsInitialPresets() {
        let run = [SavedRunPreset(name: "R", draft: RunDraft())]
        let build = [SavedBuildPreset(name: "B", draft: BuildDraft())]
        let store = InMemoryPresetStore(runPresets: run, buildPresets: build)
        XCTAssertEqual(store.loadRunPresets(), run)
        XCTAssertEqual(store.loadBuildPresets(), build)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `make test`. Expected: compile error (`SavedRunPreset`/`InMemoryPresetStore` undefined).

- [ ] **Step 3: Create `Presets.swift`.** Write `Sources/CapsuleDomain/Presets.swift`:
```swift
//
//  Presets.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Concrete
//  persistence (UserDefaults) lives in the composition root so the domain owns no
//  storage-key knowledge; this file defines the saved-preset value types, the seam, and
//  an in-memory double — mirroring the `ScopeStore` triad.

import Foundation

/// A named, saved Quick Run configuration, re-invokable from the palette or menu.
public struct SavedRunPreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var draft: RunDraft

    public init(id: UUID = UUID(), name: String, draft: RunDraft) {
        self.id = id
        self.name = name
        self.draft = draft
    }
}

/// A named, saved Build configuration, re-invokable from the palette or menu.
public struct SavedBuildPreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var draft: BuildDraft

    public init(id: UUID = UUID(), name: String, draft: BuildDraft) {
        self.id = id
        self.name = name
        self.draft = draft
    }
}

/// Persists the user's saved Run/Build presets. Injected into ``RunModel``/``BuildModel`` so
/// the domain stays free of any concrete persistence and remains unit-testable.
public protocol PresetStore: Sendable {
    func loadRunPresets() -> [SavedRunPreset]
    func saveRunPresets(_ presets: [SavedRunPreset])
    func loadBuildPresets() -> [SavedBuildPreset]
    func saveBuildPresets(_ presets: [SavedBuildPreset])
}

/// A thread-safe, in-memory ``PresetStore`` — the models' default (ephemeral) and the
/// test double.
public final class InMemoryPresetStore: PresetStore, @unchecked Sendable {
    private let lock = NSLock()
    private var runPresets: [SavedRunPreset]
    private var buildPresets: [SavedBuildPreset]

    public init(
        runPresets: [SavedRunPreset] = [],
        buildPresets: [SavedBuildPreset] = []
    ) {
        self.runPresets = runPresets
        self.buildPresets = buildPresets
    }

    public func loadRunPresets() -> [SavedRunPreset] {
        lock.lock()
        defer { lock.unlock() }
        return runPresets
    }

    public func saveRunPresets(_ presets: [SavedRunPreset]) {
        lock.lock()
        defer { lock.unlock() }
        runPresets = presets
    }

    public func loadBuildPresets() -> [SavedBuildPreset] {
        lock.lock()
        defer { lock.unlock() }
        return buildPresets
    }

    public func saveBuildPresets(_ presets: [SavedBuildPreset]) {
        lock.lock()
        defer { lock.unlock() }
        buildPresets = presets
    }
}
```

- [ ] **Step 4: Run — expect PASS.** `make test`. Expected: the three new tests pass; suite green.

- [ ] **Step 5: Commit.**
```
feat(presets): add SavedRun/BuildPreset + PresetStore + InMemoryPresetStore

Domain value types and the persistence seam, mirroring the ScopeStore triad
(protocol + in-memory double). Concrete UserDefaults store lands next.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P3.3: `UserDefaultsPresetStore` (composition root)

**Files:**
- Create: `Sources/CapsuleApp/UserDefaultsPresetStore.swift`
- Test: Create `Tests/CapsuleUnitTests/UserDefaultsPresetStoreTests.swift`

**Interfaces:**
- Consumes: `PresetStore`, `SavedRunPreset`, `SavedBuildPreset` (from `CapsuleDomain`).
- Produces: `struct UserDefaultsPresetStore: PresetStore` (keys `capsule.runPresets` / `capsule.buildPresets`, JSON encode/decode, corrupt/missing → empty list); `init(defaults: UserDefaults = .standard)`.

- [ ] **Step 1: Write the failing persistence test.** Create `Tests/CapsuleUnitTests/UserDefaultsPresetStoreTests.swift`:
```swift
//
//  UserDefaultsPresetStoreTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import XCTest

@testable import CapsuleApp

final class UserDefaultsPresetStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "capsule.tests.\(UUID().uuidString)")!
    }

    func testRunPresetsPersistAcrossInstances() {
        let defaults = makeDefaults()
        let store = UserDefaultsPresetStore(defaults: defaults)
        XCTAssertTrue(store.loadRunPresets().isEmpty)
        let presets = [SavedRunPreset(name: "Web", draft: RunDraft(image: "nginx"))]
        store.saveRunPresets(presets)
        let reread = UserDefaultsPresetStore(defaults: defaults)
        XCTAssertEqual(reread.loadRunPresets(), presets)
    }

    func testBuildPresetsPersistContextDirectory() {
        let defaults = makeDefaults()
        let store = UserDefaultsPresetStore(defaults: defaults)
        var draft = BuildDraft()
        draft.contextDirectory = URL(fileURLWithPath: "/tmp/project")
        draft.tag = "app:dev"
        store.saveBuildPresets([SavedBuildPreset(name: "App", draft: draft)])
        let reread = UserDefaultsPresetStore(defaults: defaults)
        XCTAssertEqual(
            reread.loadBuildPresets().first?.draft.contextDirectory?.path, "/tmp/project")
    }

    func testCorruptDataFallsBackToEmpty() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "capsule.runPresets")
        let store = UserDefaultsPresetStore(defaults: defaults)
        XCTAssertTrue(store.loadRunPresets().isEmpty)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `make test`. Expected: compile error (`UserDefaultsPresetStore` undefined).

- [ ] **Step 3: Create `UserDefaultsPresetStore.swift`.** Write `Sources/CapsuleApp/UserDefaultsPresetStore.swift` (mirrors `UserDefaultsScopeStore` exactly):
```swift
//
//  UserDefaultsPresetStore.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The concrete `PresetStore` for saved Run/Build presets. It lives in the composition root
//  (not the domain) so the persistence keys and JSON encoding stay out of `CapsuleDomain`.

import CapsuleDomain
import Foundation

struct UserDefaultsPresetStore: PresetStore {
    // `UserDefaults` is thread-safe but not yet `Sendable`-annotated; the store conforms
    // to the `Sendable` `PresetStore` seam, so opt the reference out of the check.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let runKey = "capsule.runPresets"
    private let buildKey = "capsule.buildPresets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadRunPresets() -> [SavedRunPreset] {
        guard
            let data = defaults.data(forKey: runKey),
            let presets = try? JSONDecoder().decode([SavedRunPreset].self, from: data)
        else {
            return []
        }
        return presets
    }

    func saveRunPresets(_ presets: [SavedRunPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: runKey)
    }

    func loadBuildPresets() -> [SavedBuildPreset] {
        guard
            let data = defaults.data(forKey: buildKey),
            let presets = try? JSONDecoder().decode([SavedBuildPreset].self, from: data)
        else {
            return []
        }
        return presets
    }

    func saveBuildPresets(_ presets: [SavedBuildPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: buildKey)
    }
}
```

- [ ] **Step 4: Run — expect PASS.** `make test`. Expected: the four new tests pass; suite green.

- [ ] **Step 5: Commit.**
```
feat(presets): add UserDefaultsPresetStore in composition root

JSON-backed PresetStore under capsule.runPresets / capsule.buildPresets,
corrupt/missing → empty list. Mirrors UserDefaultsScopeStore exactly.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P3.4: Preset methods on `RunModel`

**Files:**
- Modify: `Sources/CapsuleDomain/RunModel.swift:48-76` (add `presetStore` stored prop + init param + assignment), `:39-47` (add `runPresets` property), and append the preset methods.
- Test: Create `Tests/CapsuleUnitTests/RunModelPresetTests.swift`

**Interfaces:**
- Consumes: `PresetStore`, `InMemoryPresetStore`, `SavedRunPreset` (from P3.2).
- Produces: `RunModel.init(..., presetStore: any PresetStore = InMemoryPresetStore())`; `public private(set) var runPresets: [SavedRunPreset]`; `func loadPresets()`; `func savePreset(name: String)`; `func deletePreset(_ preset: SavedRunPreset)`; `func apply(_ preset: SavedRunPreset)`.

- [ ] **Step 1: Write the failing model test.** Create `Tests/CapsuleUnitTests/RunModelPresetTests.swift`:
```swift
//
//  RunModelPresetTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class RunModelPresetTests: XCTestCase {
    func testSavePersistsAndApplyLoadsDraftInAFreshModel() throws {
        let store = InMemoryPresetStore()
        let model = RunModel(backend: MockBackend(), taskCenter: TaskCenter(), presetStore: store)
        model.loadPresets()
        XCTAssertTrue(model.runPresets.isEmpty)

        model.draft.image = "nginx:latest"
        model.draft.portRows = ["8080:80"]
        model.savePreset(name: "Web")
        XCTAssertEqual(model.runPresets.count, 1)
        XCTAssertEqual(store.loadRunPresets().first?.name, "Web")

        // A fresh model backed by the same store sees and applies the saved preset.
        let reopened = RunModel(
            backend: MockBackend(), taskCenter: TaskCenter(), presetStore: store)
        reopened.loadPresets()
        let preset = try XCTUnwrap(reopened.runPresets.first)
        reopened.apply(preset)
        XCTAssertEqual(reopened.draft.image, "nginx:latest")
        XCTAssertEqual(reopened.draft.portRows, ["8080:80"])
    }

    func testDeleteRemovesFromModelAndStore() throws {
        let store = InMemoryPresetStore()
        let model = RunModel(backend: MockBackend(), taskCenter: TaskCenter(), presetStore: store)
        model.draft.image = "alpine"
        model.savePreset(name: "A")
        let preset = try XCTUnwrap(model.runPresets.first)
        model.deletePreset(preset)
        XCTAssertTrue(model.runPresets.isEmpty)
        XCTAssertTrue(store.loadRunPresets().isEmpty)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `make test`. Expected: compile error (`RunModel` has no `presetStore:` param / `runPresets` / preset methods).

- [ ] **Step 3: Add the `runPresets` published property.** In `Sources/CapsuleDomain/RunModel.swift`, just after the existing `lastFailedTask` declaration (currently `public private(set) var lastFailedTask: OperationTask?` at line 46), add:
```swift
    /// The user's saved run presets, loaded from the injected ``PresetStore``.
    public private(set) var runPresets: [SavedRunPreset] = []
```

- [ ] **Step 4: Add the `presetStore` dependency.** In the stored-property block (after `private let copyCommand: @MainActor ([String]) -> Void` at line 55), add:
```swift
    private let presetStore: any PresetStore
```
Then add the init parameter — change the end of the init signature (currently `copyCommand: @escaping @MainActor ([String]) -> Void = { _ in }`) to append a new parameter:
```swift
        copyCommand: @escaping @MainActor ([String]) -> Void = { _ in },
        presetStore: any PresetStore = InMemoryPresetStore()
```
And in the init body, after `self.copyCommand = copyCommand` (line 75), add:
```swift
        self.presetStore = presetStore
```

- [ ] **Step 5: Add the preset methods.** Append inside the `RunModel` class (e.g. just before the closing `private func cleaned(...)` helper) in `Sources/CapsuleDomain/RunModel.swift`:
```swift
    // MARK: Saved presets

    /// Loads saved run presets from the store into ``runPresets``.
    public func loadPresets() {
        runPresets = presetStore.loadRunPresets()
    }

    /// Saves the current draft as a new named preset and persists the list.
    public func savePreset(name: String) {
        let preset = SavedRunPreset(name: name, draft: draft)
        runPresets.append(preset)
        presetStore.saveRunPresets(runPresets)
        onActivity("Saved run preset “\(name)”.")
    }

    /// Removes a preset and persists the updated list.
    public func deletePreset(_ preset: SavedRunPreset) {
        runPresets.removeAll { $0.id == preset.id }
        presetStore.saveRunPresets(runPresets)
    }

    /// Loads a preset's draft into the sheet, ready to run.
    public func apply(_ preset: SavedRunPreset) {
        draft = preset.draft
    }
```

- [ ] **Step 6: Run — expect PASS.** `make test`. Expected: both new tests pass; existing `RunModelTests` still green (the new init param is defaulted, so call-sites compile unchanged).

- [ ] **Step 7: Commit.**
```
feat(presets): add load/save/delete/apply preset methods to RunModel

RunModel takes an injected PresetStore (default InMemoryPresetStore),
exposes runPresets, and gains loadPresets/savePreset/deletePreset/apply —
mirroring ContainerBrowserModel's scope methods.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P3.5: Preset methods on `BuildModel`

**Files:**
- Modify: `Sources/CapsuleDomain/BuildModel.swift:48-70` (add `presetStore` stored prop + init param + assignment), `:49` (add `buildPresets` property), and append the preset methods.
- Test: Create `Tests/CapsuleUnitTests/BuildModelPresetTests.swift`

**Interfaces:**
- Consumes: `PresetStore`, `InMemoryPresetStore`, `SavedBuildPreset` (from P3.2).
- Produces: `BuildModel.init(..., presetStore: any PresetStore = InMemoryPresetStore())`; `public private(set) var buildPresets: [SavedBuildPreset]`; `func loadPresets()`; `func savePreset(name: String)`; `func deletePreset(_ preset: SavedBuildPreset)`; `func apply(_ preset: SavedBuildPreset)`.

- [ ] **Step 1: Write the failing model test.** Create `Tests/CapsuleUnitTests/BuildModelPresetTests.swift`:
```swift
//
//  BuildModelPresetTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class BuildModelPresetTests: XCTestCase {
    func testSavePersistsContextDirectoryAndApplyLoadsDraft() throws {
        let store = InMemoryPresetStore()
        let model = BuildModel(backend: MockBackend(), taskCenter: TaskCenter(), presetStore: store)
        model.loadPresets()
        XCTAssertTrue(model.buildPresets.isEmpty)

        model.draft.contextDirectory = URL(fileURLWithPath: "/tmp/project")
        model.draft.tag = "app:dev"
        model.savePreset(name: "App")
        XCTAssertEqual(store.loadBuildPresets().first?.name, "App")

        let reopened = BuildModel(
            backend: MockBackend(), taskCenter: TaskCenter(), presetStore: store)
        reopened.loadPresets()
        let preset = try XCTUnwrap(reopened.buildPresets.first)
        reopened.apply(preset)
        XCTAssertEqual(reopened.draft.contextDirectory?.path, "/tmp/project")
        XCTAssertEqual(reopened.draft.tag, "app:dev")
    }

    func testDeleteRemovesFromStore() throws {
        let store = InMemoryPresetStore()
        let model = BuildModel(backend: MockBackend(), taskCenter: TaskCenter(), presetStore: store)
        model.draft.tag = "t:1"
        model.savePreset(name: "B")
        let preset = try XCTUnwrap(model.buildPresets.first)
        model.deletePreset(preset)
        XCTAssertTrue(store.loadBuildPresets().isEmpty)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `make test`. Expected: compile error (`BuildModel` has no `presetStore:` param / `buildPresets` / preset methods).

- [ ] **Step 3: Add the `buildPresets` published property.** In `Sources/CapsuleDomain/BuildModel.swift`, just after `public var draft = BuildDraft()` (line 49), add:
```swift
    /// The user's saved build presets, loaded from the injected ``PresetStore``.
    public private(set) var buildPresets: [SavedBuildPreset] = []
```

- [ ] **Step 4: Add the `presetStore` dependency.** In the stored-property block (after `private let reloadList: @MainActor () async -> Void` at line 56), add:
```swift
    private let presetStore: any PresetStore
```
Then append a parameter to the init signature — change the last init parameter (currently `reloadList: @escaping @MainActor () async -> Void = {}`) to:
```swift
        reloadList: @escaping @MainActor () async -> Void = {},
        presetStore: any PresetStore = InMemoryPresetStore()
```
And in the init body, after `self.reloadList = reloadList` (line 69), add:
```swift
        self.presetStore = presetStore
```

- [ ] **Step 5: Add the preset methods.** Append inside the `BuildModel` class (e.g. just before the `private func start(_ config:)` helper) in `Sources/CapsuleDomain/BuildModel.swift`:
```swift
    // MARK: Saved presets

    /// Loads saved build presets from the store into ``buildPresets``.
    public func loadPresets() {
        buildPresets = presetStore.loadBuildPresets()
    }

    /// Saves the current draft as a new named preset and persists the list.
    public func savePreset(name: String) {
        let preset = SavedBuildPreset(name: name, draft: draft)
        buildPresets.append(preset)
        presetStore.saveBuildPresets(buildPresets)
        onActivity("Saved build preset “\(name)”.")
    }

    /// Removes a preset and persists the updated list.
    public func deletePreset(_ preset: SavedBuildPreset) {
        buildPresets.removeAll { $0.id == preset.id }
        presetStore.saveBuildPresets(buildPresets)
    }

    /// Loads a preset's draft into the sheet, ready to build.
    public func apply(_ preset: SavedBuildPreset) {
        draft = preset.draft
    }
```

- [ ] **Step 6: Run — expect PASS.** `make test`. Expected: both new tests pass; existing `BuildModelTests` still green (defaulted init param).

- [ ] **Step 7: Commit.**
```
feat(presets): add load/save/delete/apply preset methods to BuildModel

BuildModel takes an injected PresetStore (default InMemoryPresetStore),
exposes buildPresets, and gains loadPresets/savePreset/deletePreset/apply.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P3.6: Save / apply / delete run presets in `QuickRunSheet`

**Files:**
- Modify: `Sources/CapsuleUI/QuickRunSheet.swift:15-20` (sheet `@State`), `:22-40` (body — `.task`/`.alert`), `:42-49` (header — Presets menu)

**Interfaces:**
- Consumes: `RunModel.runPresets`, `RunModel.loadPresets()`, `RunModel.savePreset(name:)`, `RunModel.deletePreset(_:)`, `RunModel.apply(_:)` (from P3.4).
- Produces: none (UI). No unit test — build-verified; model methods covered by P3.4; GUI smoke in Phase 6.

- [ ] **Step 1: Add the sheet state.** In `Sources/CapsuleUI/QuickRunSheet.swift`, after the existing `@State private var activeTask: OperationTask?` (line 20), add:
```swift
    @State private var showingSavePreset = false
    @State private var newPresetName = ""
```

- [ ] **Step 2: Load presets + present the Save alert.** In `body`, after the existing `.frame(width: 540, height: 620)` (line 39), append:
```swift
        .task { model.loadPresets() }
        .alert("Save Run Preset", isPresented: $showingSavePreset) {
            TextField("Preset name", text: $newPresetName)
            Button("Save") {
                let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { model.savePreset(name: name) }
                newPresetName = ""
            }
            Button("Cancel", role: .cancel) { newPresetName = "" }
        } message: {
            Text("Saves the current run configuration as a reusable preset.")
        }
```

- [ ] **Step 3: Add the Presets menu to the header.** Replace the existing `header` computed property (lines 42-49) with:
```swift
    private var header: some View {
        HStack {
            Label("Run a Container", systemImage: "play.rectangle")
                .font(.headline)
            Spacer()
            presetsMenu
        }
        .padding(12)
    }

    private var presetsMenu: some View {
        Menu {
            if model.runPresets.isEmpty {
                Text("No saved presets")
            } else {
                ForEach(model.runPresets) { preset in
                    Button(preset.name) { model.apply(preset) }
                }
                Divider()
                Menu("Delete Preset") {
                    ForEach(model.runPresets) { preset in
                        Button(preset.name, role: .destructive) { model.deletePreset(preset) }
                    }
                }
            }
            Divider()
            Button("Save as Preset…") {
                newPresetName = ""
                showingSavePreset = true
            }
        } label: {
            Label("Presets", systemImage: "square.stack.3d.up")
        }
        .help("Saved run presets")
    }
```

- [ ] **Step 4: Build.** `make build`. Expected: success.

- [ ] **Step 5: Commit.**
```
feat(presets): save/apply/delete run presets in QuickRunSheet

Header Presets menu (apply + delete submenu) and a Save-as-preset alert,
mirroring the Save Scope alert + scopes menu pattern.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P3.7: Save / apply / delete build presets in `BuildSheet`

**Files:**
- Modify: `Sources/CapsuleUI/BuildSheet.swift:20-22` (sheet `@State`), `:24-59` (body — header menu + `.task`/`.alert`), and append a `presetsMenu` helper.

**Interfaces:**
- Consumes: `BuildModel.buildPresets`, `BuildModel.loadPresets()`, `BuildModel.savePreset(name:)`, `BuildModel.deletePreset(_:)`, `BuildModel.apply(_:)` (from P3.5).
- Produces: none (UI). No unit test — build-verified; model methods covered by P3.5; GUI smoke in Phase 6.

- [ ] **Step 1: Add the sheet state.** In `Sources/CapsuleUI/BuildSheet.swift`, after the existing `@State private var isDropTargeted = false` (line 22), add:
```swift
    @State private var showingSavePreset = false
    @State private var newPresetName = ""
```

- [ ] **Step 2: Add the Presets menu to the header HStack.** In `body`, change the header `HStack` (currently lines 26-31) to add the menu after `Spacer()`:
```swift
            HStack {
                Label("Build an Image", systemImage: "hammer")
                    .font(.headline)
                Spacer()
                presetsMenu
            }
            .padding(12)
```

- [ ] **Step 3: Load presets + present the Save alert.** In `body`, after the existing `.frame(width: 560, height: 640)` (line 58), append:
```swift
        .task { model.loadPresets() }
        .alert("Save Build Preset", isPresented: $showingSavePreset) {
            TextField("Preset name", text: $newPresetName)
            Button("Save") {
                let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { model.savePreset(name: name) }
                newPresetName = ""
            }
            Button("Cancel", role: .cancel) { newPresetName = "" }
        } message: {
            Text("Saves the current build configuration as a reusable preset.")
        }
```

- [ ] **Step 4: Add the `presetsMenu` helper.** Add this computed property to the `BuildSheet` struct (e.g. just after the `dropZone` property):
```swift
    private var presetsMenu: some View {
        Menu {
            if model.buildPresets.isEmpty {
                Text("No saved presets")
            } else {
                ForEach(model.buildPresets) { preset in
                    Button(preset.name) { model.apply(preset) }
                }
                Divider()
                Menu("Delete Preset") {
                    ForEach(model.buildPresets) { preset in
                        Button(preset.name, role: .destructive) { model.deletePreset(preset) }
                    }
                }
            }
            Divider()
            Button("Save as Preset…") {
                newPresetName = ""
                showingSavePreset = true
            }
        } label: {
            Label("Presets", systemImage: "square.stack.3d.up")
        }
        .help("Saved build presets")
    }
```

- [ ] **Step 5: Build.** `make build`. Expected: success.

- [ ] **Step 6: Commit.**
```
feat(presets): save/apply/delete build presets in BuildSheet

Header Presets menu (apply + delete submenu) and a Save-as-preset alert,
mirroring the QuickRunSheet preset UX.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

---

### Task P3.8: Inject `UserDefaultsPresetStore` in the composition root

**Files:**
- Modify: `Sources/CapsuleApp/AppEnvironment.swift:234-250` (construct a shared store and pass it to the `RunModel` and `BuildModel` inits)

**Interfaces:**
- Consumes: `UserDefaultsPresetStore` (from P3.3); `RunModel.init(..., presetStore:)` (P3.4); `BuildModel.init(..., presetStore:)` (P3.5).
- Produces: none (wiring). Verified by the existing `CompositionTests`/`AppEnvironmentActionsTests` building + green suite.

- [ ] **Step 1: Build + full test (baseline).** `make test`. Expected: green (everything from P3.1–P3.7 in place; this task only wires the live store).

- [ ] **Step 2: Construct the shared store and inject it.** In `Sources/CapsuleApp/AppEnvironment.swift`, in `live()`, immediately before the `let runModel = RunModel(` line (line 234) add:
```swift
        let presetStore = UserDefaultsPresetStore()
```
Then change the `runModel` construction (currently lines 234-243) to pass the store — append the new argument after `copyCommand:`:
```swift
        let runModel = RunModel(
            backend: backend,
            taskCenter: taskCenter,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            reloadList: { await browserModel.refresh() },
            terminalAvailable: { true },
            launchTerminal: { request in shell.openTerminal(request) },
            copyCommand: copyCommandToClipboard,
            presetStore: presetStore
        )
```
And change the `buildModel` construction (currently lines 244-250) to pass the same store — append after `reloadList:`:
```swift
        let buildModel = BuildModel(
            backend: backend,
            taskCenter: taskCenter,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            reloadList: { await imageBrowserModel.refresh() },
            presetStore: presetStore
        )
```

- [ ] **Step 3: Build + full test.** `make build` then `make test`. Expected: green (wiring only; no behavior tests change). The live Run/Build sheets now persist presets to `UserDefaults`.

- [ ] **Step 4: Commit.**
```
feat(presets): inject UserDefaultsPresetStore into Run/BuildModel

AppEnvironment.live() builds one UserDefaultsPresetStore and threads it into
both RunModel and BuildModel, so saved presets persist across launches.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

# Phase 4 — Terminal passthrough + plugin discovery

This phase builds the power-user escape hatches that ensure nothing in Capsule is a dead end. It adds the **plugin discovery seam** — `PluginInfo` + `PluginDiscovering` + `PluginCatalogModel` in `CapsuleDomain`, with a concrete `LibexecPluginScanner` in `CapsuleApp` that scans the two libexec plugin directories and is gated on the service running — and the **Command Console** (`CommandConsoleView` in `CapsuleUI`), a single editable-argv surface seeded from a `CommandInvocation` that backs both the standalone raw-command-preview action and the universal terminal passthrough (copy, or escalate to the embedded terminal / external Terminal.app). All four pieces are pure value/seam types or a closure-driven view, so each is unit-tested in isolation; the composition-root wiring and palette/menu presentation land in Phase 5.

### Task P4.1: Plugin value type + discovery seam

**Files:**
- Create: `Sources/CapsuleDomain/PluginCatalog.swift`
- Test: `Tests/CapsuleUnitTests/PluginCatalogTypesTests.swift`

**Interfaces:**
- Produces: `struct PluginInfo: Identifiable, Equatable, Sendable { var name: String; var path: String; var id: String { name }; init(name: String, path: String) }`; `protocol PluginDiscovering: Sendable { func installedPlugins() -> [PluginInfo] }`; `struct NoPluginDiscovery: PluginDiscovering { init(); func installedPlugins() -> [PluginInfo] }`.

- [ ] **Step 1: Write the failing test**

Create `Tests/CapsuleUnitTests/PluginCatalogTypesTests.swift`:
```swift
//
//  PluginCatalogTypesTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import XCTest

final class PluginCatalogTypesTests: XCTestCase {
    func testPluginInfoIdentifiesByName() {
        let info = PluginInfo(
            name: "buildx",
            path: "/usr/local/libexec/container-plugins/container-buildx")
        XCTAssertEqual(info.id, "buildx")
        XCTAssertEqual(info.name, "buildx")
        XCTAssertEqual(info.path, "/usr/local/libexec/container-plugins/container-buildx")
    }

    func testNoPluginDiscoveryReturnsEmpty() {
        XCTAssertEqual(NoPluginDiscovery().installedPlugins(), [])
    }
}
```

- [ ] **Step 2: Run it — expect FAIL.** Run `make test`. Expected: compile error `cannot find 'PluginInfo' in scope` / `cannot find 'NoPluginDiscovery' in scope`.

- [ ] **Step 3: Add the value type + seam**

Create `Sources/CapsuleDomain/PluginCatalog.swift`:
```swift
//
//  PluginCatalog.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Plugin discovery is
//  modeled behind a pure `PluginDiscovering` seam so the domain stays decoupled from the
//  filesystem; the concrete `LibexecPluginScanner` lives in the composition root (CapsuleApp).

/// A `container` plugin resolved from a libexec directory: an external `container-<name>`
/// binary invoked as the subcommand `container <name>`.
public struct PluginInfo: Identifiable, Equatable, Sendable {
    /// The subcommand name (the part after the `container-` prefix).
    public var name: String
    /// The absolute path of the backing `container-<name>` executable.
    public var path: String
    public var id: String { name }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

/// The seam for enumerating installed `container` plugins. Pure data out; the concrete
/// scanner (a filesystem walk) is injected by the composition root so the domain is testable
/// with a fake.
public protocol PluginDiscovering: Sendable {
    func installedPlugins() -> [PluginInfo]
}

/// The inert default used by previews/tests with no real scanner wired.
public struct NoPluginDiscovery: PluginDiscovering {
    public init() {}
    public func installedPlugins() -> [PluginInfo] { [] }
}
```

- [ ] **Step 4: Run it — expect PASS.** Run `make test`. Expected: `PluginCatalogTypesTests` green, full suite green.

- [ ] **Step 5: Commit**

```
git add Sources/CapsuleDomain/PluginCatalog.swift Tests/CapsuleUnitTests/PluginCatalogTypesTests.swift
git commit -m "$(cat <<'EOF'
feat(plugins): add PluginInfo + PluginDiscovering seam

Pure Domain value type + discovery protocol (with an inert NoPluginDiscovery
default) for the libexec plugin catalog. Filesystem scanning is kept behind the
seam so the domain stays Process-free and testable with a fake.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
EOF
)"
```

---

### Task P4.2: `PluginCatalogModel` (gated list + terminal route)

**Files:**
- Modify: `Sources/CapsuleDomain/PluginCatalog.swift` (add `import Observation`; append `PluginCatalogModel`)
- Test: `Tests/CapsuleUnitTests/PluginCatalogModelTests.swift`

**Interfaces:**
- Consumes: `PluginInfo`, `PluginDiscovering` (Task P4.1); existing `TerminalRequest(containerID: String?, title: String, argv: [String], kind: TerminalRequest.Kind)` with `.runInteractive` (verified in `Sources/CapsuleDomain/TerminalRequest.swift`).
- Produces: `@MainActor @Observable final class PluginCatalogModel { init(discovering: any PluginDiscovering, isServiceRunning: @escaping @MainActor () -> Bool); private(set) var plugins: [PluginInfo]; func refresh(); func terminalRequest(for plugin: PluginInfo) -> TerminalRequest }`.

- [ ] **Step 1: Write the failing test**

Create `Tests/CapsuleUnitTests/PluginCatalogModelTests.swift`:
```swift
//
//  PluginCatalogModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import XCTest

private struct FakeDiscovery: PluginDiscovering {
    let plugins: [PluginInfo]
    func installedPlugins() -> [PluginInfo] { plugins }
}

@MainActor
final class PluginCatalogModelTests: XCTestCase {
    private let sample = [
        PluginInfo(name: "buildx", path: "/p/container-buildx"),
        PluginInfo(name: "compose", path: "/p/container-compose"),
    ]

    func testRefreshIsEmptyWhenServiceStopped() {
        let model = PluginCatalogModel(
            discovering: FakeDiscovery(plugins: sample), isServiceRunning: { false })
        model.refresh()
        XCTAssertEqual(model.plugins, [])
    }

    func testRefreshListsPluginsWhenServiceRunning() {
        let model = PluginCatalogModel(
            discovering: FakeDiscovery(plugins: sample), isServiceRunning: { true })
        model.refresh()
        XCTAssertEqual(model.plugins, sample)
    }

    func testTerminalRequestRoutesContainerSubcommand() {
        let model = PluginCatalogModel(
            discovering: FakeDiscovery(plugins: sample), isServiceRunning: { true })
        let request = model.terminalRequest(for: sample[0])
        XCTAssertNil(request.containerID)
        XCTAssertEqual(request.title, "container buildx")
        XCTAssertEqual(request.argv, ["container", "buildx"])
        XCTAssertEqual(request.kind, .runInteractive)
    }
}
```

- [ ] **Step 2: Run it — expect FAIL.** Run `make test`. Expected: compile error `cannot find 'PluginCatalogModel' in scope`.

- [ ] **Step 3: Add the model**

In `Sources/CapsuleDomain/PluginCatalog.swift`, add the import below the header comment (it currently has no `import` line):
```swift
import Observation
```
Then append the model to the end of the file:
```swift

/// Exposes the installed plugins for the palette/menu, gated on the system service running
/// (plugins require it). Each plugin is surfaced as a terminal route since Capsule has no
/// first-class UI for plugins.
@MainActor
@Observable
public final class PluginCatalogModel {
    public private(set) var plugins: [PluginInfo] = []

    private let discovering: any PluginDiscovering
    private let isServiceRunning: @MainActor () -> Bool

    public init(
        discovering: any PluginDiscovering,
        isServiceRunning: @escaping @MainActor () -> Bool
    ) {
        self.discovering = discovering
        self.isServiceRunning = isServiceRunning
    }

    /// Re-reads installed plugins while the service is running; otherwise clears the list so
    /// stale entries never linger after a shutdown.
    public func refresh() {
        plugins = isServiceRunning() ? discovering.installedPlugins() : []
    }

    /// A terminal route for a plugin subcommand: `container <name>` opened interactively.
    public func terminalRequest(for plugin: PluginInfo) -> TerminalRequest {
        TerminalRequest(
            containerID: nil,
            title: "container \(plugin.name)",
            argv: ["container", plugin.name],
            kind: .runInteractive)
    }
}
```

- [ ] **Step 4: Run it — expect PASS.** Run `make test`. Expected: `PluginCatalogModelTests` green, full suite green.

- [ ] **Step 5: Commit**

```
git add Sources/CapsuleDomain/PluginCatalog.swift Tests/CapsuleUnitTests/PluginCatalogModelTests.swift
git commit -m "$(cat <<'EOF'
feat(plugins): add PluginCatalogModel gated on the running service

Observable Domain model that refreshes the plugin list only while the service
is up and maps each plugin to a `container <name>` interactive TerminalRequest.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
EOF
)"
```

---

### Task P4.3: `LibexecPluginScanner` (filesystem discovery in the composition root)

**Files:**
- Create: `Sources/CapsuleApp/LibexecPluginScanner.swift`
- Test: `Tests/CapsuleUnitTests/LibexecPluginScannerTests.swift`

**Interfaces:**
- Consumes: `PluginDiscovering`, `PluginInfo` (Task P4.1).
- Produces: `struct LibexecPluginScanner: PluginDiscovering { init(directories: [String] = ["/usr/local/libexec/container-plugins", "/usr/local/libexec/container/plugins"], fileManager: FileManager = .default); func installedPlugins() -> [PluginInfo] }` — returns one `PluginInfo` per entry that begins `container-` and is an executable regular file; `name` is the part after the prefix; deduped by name (first directory wins).

- [ ] **Step 1: Write the failing test**

Create `Tests/CapsuleUnitTests/LibexecPluginScannerTests.swift` (mirrors the `@testable import CapsuleApp` precedent in `CompositionTests.swift`):
```swift
//
//  LibexecPluginScannerTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import XCTest

@testable import CapsuleApp

final class LibexecPluginScannerTests: XCTestCase {
    private let fm = FileManager.default

    private func makeExecutable(_ url: URL) throws {
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makeNonExecutable(_ url: URL) throws {
        try Data("x".utf8).write(to: url)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }

    func testScansPrefixedExecutablesIgnoringTheRestAndDedupes() throws {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dirA = root.appendingPathComponent("a")
        let dirB = root.appendingPathComponent("b")
        try fm.createDirectory(at: dirA, withIntermediateDirectories: true)
        try fm.createDirectory(at: dirB, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try makeExecutable(dirA.appendingPathComponent("container-buildx"))
        try makeExecutable(dirA.appendingPathComponent("container-compose"))
        try makeExecutable(dirA.appendingPathComponent("helper"))           // no prefix → ignored
        try makeNonExecutable(dirA.appendingPathComponent("container-doc")) // not exec → ignored
        try fm.createDirectory(                                              // dir → ignored
            at: dirA.appendingPathComponent("container-dir"),
            withIntermediateDirectories: true)
        try makeExecutable(dirB.appendingPathComponent("container-buildx"))  // dup name → deduped
        try makeExecutable(dirB.appendingPathComponent("container-extra"))

        let scanner = LibexecPluginScanner(directories: [dirA.path, dirB.path])
        let plugins = scanner.installedPlugins()

        XCTAssertEqual(Set(plugins.map(\.name)), ["buildx", "compose", "extra"])
        XCTAssertEqual(plugins.count, 3)
        // First directory wins on a name collision.
        XCTAssertEqual(
            plugins.first { $0.name == "buildx" }?.path,
            dirA.appendingPathComponent("container-buildx").path)
    }

    func testMissingDirectoriesReturnEmptyCleanly() {
        let scanner = LibexecPluginScanner(
            directories: ["/no/such/dir/\(UUID().uuidString)"])
        XCTAssertEqual(scanner.installedPlugins(), [])
    }
}
```

- [ ] **Step 2: Run it — expect FAIL.** Run `make test`. Expected: compile error `cannot find 'LibexecPluginScanner' in scope`.

- [ ] **Step 3: Add the scanner**

Create `Sources/CapsuleApp/LibexecPluginScanner.swift`:
```swift
//
//  LibexecPluginScanner.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The concrete `PluginDiscovering` for the composition root. It scans the two libexec
//  plugin directories the `container` resolver itself names and surfaces each `container-*`
//  executable as a plugin. It lives here (not the domain) so the filesystem walk stays out of
//  `CapsuleDomain`, which must remain Process- and IO-free.

import CapsuleDomain
import Foundation

struct LibexecPluginScanner: PluginDiscovering {
    private let directories: [String]
    private let fileManager: FileManager

    init(
        directories: [String] = [
            "/usr/local/libexec/container-plugins",
            "/usr/local/libexec/container/plugins",
        ],
        fileManager: FileManager = .default
    ) {
        self.directories = directories
        self.fileManager = fileManager
    }

    func installedPlugins() -> [PluginInfo] {
        let prefix = "container-"
        var seen: Set<String> = []
        var result: [PluginInfo] = []
        for directory in directories {
            let entries = (try? fileManager.contentsOfDirectory(atPath: directory)) ?? []
            for entry in entries.sorted() where entry.hasPrefix(prefix) {
                let path = (directory as NSString).appendingPathComponent(entry)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                    !isDirectory.boolValue,
                    fileManager.isExecutableFile(atPath: path)
                else { continue }
                let name = String(entry.dropFirst(prefix.count))
                guard !name.isEmpty, seen.insert(name).inserted else { continue }
                result.append(PluginInfo(name: name, path: path))
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Run it — expect PASS.** Run `make test`. Expected: `LibexecPluginScannerTests` green, full suite green.

- [ ] **Step 5: Commit**

```
git add Sources/CapsuleApp/LibexecPluginScanner.swift Tests/CapsuleUnitTests/LibexecPluginScannerTests.swift
git commit -m "$(cat <<'EOF'
feat(plugins): add LibexecPluginScanner over the two libexec dirs

Concrete PluginDiscovering for the composition root: lists `container-*`
executable regular files under the two libexec plugin directories, strips the
prefix for the subcommand name, and dedupes by name (first directory wins).
Missing directories return cleanly.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
EOF
)"
```

---

### Task P4.4: `CommandConsoleView` (editable argv + terminal escalation)

**Files:**
- Create: `Sources/CapsuleUI/CommandConsoleView.swift`
- Test: `Tests/CapsuleUnitTests/CommandConsoleTests.swift`

**Interfaces:**
- Consumes: `CommandInvocation` (Phase 1 Domain — `displayString`); `CommandTokenizer.tokenize(_ input: String) -> [String]` (verified in `Sources/CapsuleDomain/CommandTokenizer.swift`); existing `TerminalRequest(containerID:title:argv:kind:)` with `.runInteractive`.
- Produces: `struct CommandConsoleView: View { init(seed: CommandInvocation?, onRunEmbedded: @escaping (TerminalRequest) -> Void, onRunExternal: @escaping ([String]) -> Void, onClose: @escaping () -> Void) }`; pure testable statics `static func seedText(for seed: CommandInvocation?) -> String` and `static func resolvedArgv(from text: String) -> [String]`.

- [ ] **Step 1: Write the failing test**

Create `Tests/CapsuleUnitTests/CommandConsoleTests.swift`:
```swift
//
//  CommandConsoleTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import CapsuleUI
import XCTest

final class CommandConsoleTests: XCTestCase {
    func testSeedTextUsesRedactedDisplayElseBarePrompt() {
        XCTAssertEqual(CommandConsoleView.seedText(for: nil), "container ")
        let seed = CommandInvocation(["run", "-it", "nginx"])
        XCTAssertEqual(CommandConsoleView.seedText(for: seed), seed.displayString)
    }

    func testResolvedArgvStripsLeadingContainerAndReprefixes() {
        XCTAssertEqual(
            CommandConsoleView.resolvedArgv(from: "container run -it nginx"),
            ["container", "run", "-it", "nginx"])
        XCTAssertEqual(
            CommandConsoleView.resolvedArgv(from: "run hello"),
            ["container", "run", "hello"])
        XCTAssertEqual(CommandConsoleView.resolvedArgv(from: "   "), ["container"])
    }
}
```

- [ ] **Step 2: Run it — expect FAIL.** Run `make test`. Expected: compile error `cannot find 'CommandConsoleView' in scope`.

- [ ] **Step 3: Add the view**

Create `Sources/CapsuleUI/CommandConsoleView.swift`:
```swift
//
//  CommandConsoleView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Command Console: an editable `container …` command field seeded from the current
//  best-fit invocation. It backs both the standalone raw-command-preview action and the
//  universal terminal passthrough — copy the command, or escalate it to the embedded terminal
//  or the external Terminal.app. The seed text is the redacted display string; the argv handed
//  to the terminals is the raw, re-tokenized command.

import AppKit
import CapsuleDomain
import SwiftUI

public struct CommandConsoleView: View {
    private let onRunEmbedded: (TerminalRequest) -> Void
    private let onRunExternal: ([String]) -> Void
    private let onClose: () -> Void

    @State private var text: String

    public init(
        seed: CommandInvocation?,
        onRunEmbedded: @escaping (TerminalRequest) -> Void,
        onRunExternal: @escaping ([String]) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onRunEmbedded = onRunEmbedded
        self.onRunExternal = onRunExternal
        self.onClose = onClose
        _text = State(initialValue: Self.seedText(for: seed))
    }

    /// The initial editor text: a seed's redacted display, or a bare `"container "` prompt.
    public static func seedText(for seed: CommandInvocation?) -> String {
        seed?.displayString ?? "container "
    }

    /// The raw argv to run: tokenize the edited text, drop a leading `container` token if the
    /// user kept it, then prepend the canonical executable so the result is always
    /// `["container", …]`.
    public static func resolvedArgv(from text: String) -> [String] {
        var tokens = CommandTokenizer.tokenize(text)
        if tokens.first == "container" { tokens.removeFirst() }
        return ["container"] + tokens
    }

    /// Whether the edited command carries a subcommand (more than the bare executable).
    private var isRunnable: Bool { Self.resolvedArgv(from: text).count > 1 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Command Console", systemImage: "terminal")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Command").font(.caption).foregroundStyle(.secondary)
                TextField("Command", text: $text, prompt: Text("container "))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .labelsHidden()
                Text("Runs the exact argv in a terminal. Edit freely; secrets are not stored.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(
                        Self.resolvedArgv(from: text).joined(separator: " "), forType: .string)
                }
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Run in Terminal.app") {
                    onRunExternal(Self.resolvedArgv(from: text))
                    onClose()
                }
                .disabled(!isRunnable)
                Button("Run in Terminal") {
                    let argv = Self.resolvedArgv(from: text)
                    onRunEmbedded(
                        TerminalRequest(
                            containerID: nil,
                            title: argv.joined(separator: " "),
                            argv: argv,
                            kind: .runInteractive))
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isRunnable)
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}
```

- [ ] **Step 4: Run it — expect PASS.** Run `make test`. Expected: `CommandConsoleTests` green, full suite green (UI module still imports no Backend module — `AppKit`/`SwiftUI`/`CapsuleDomain` only — so `ArchitectureGuardTests` stays green).

- [ ] **Step 5: Commit**

```
git add Sources/CapsuleUI/CommandConsoleView.swift Tests/CapsuleUnitTests/CommandConsoleTests.swift
git commit -m "$(cat <<'EOF'
feat(console): add CommandConsoleView passthrough surface

Editable `container …` console seeded from a CommandInvocation's redacted
display. Copy, or escalate the raw re-tokenized argv to the embedded terminal
(runInteractive TerminalRequest) or external Terminal.app via injected closures.
A leading `container` token is stripped before re-prefixing so the argv is
always `["container", …]`. Pure seedText/resolvedArgv statics are unit-tested.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
EOF
)"
```

# Phase 5 — Command catalog -> palette + menus + navigation

This phase unifies every power-user action behind a single source of truth: a `CommandCatalog` that both the ⌘K palette and the menu bar render, so the keyboard surface and the menu surface provably can't drift. It adds the `ShellState` plumbing (`systemTab` deep-link, `commandPalettePresented`, `pendingSheet`/`AppSheetIntent`), a pure `FuzzyMatch` ranker in Domain, the `CommandPaletteView` overlay, the menu wiring in `CapsuleCommands`, and the composition-root assembly of `CommandContext` + `PluginCatalogModel` in `AppEnvironment.live()`. All of it threads the existing `CapsuleScene` `@State` models through unchanged — no new model layer, only navigation/presentation glue.

---

### Task P5.1: `SystemTab`, `AppSheetIntent`, and `ShellState` navigation state

**Files:**
- Create: `Sources/CapsuleUI/SystemTab.swift`
- Create: `Sources/CapsuleUI/AppSheetIntent.swift`
- Modify: `Sources/CapsuleUI/ShellState.swift:49-112` (add stored state + init params + methods)
- Test: `Tests/CapsuleUnitTests/ShellNavigationTests.swift`

**Interfaces:**
- Consumes: `SidebarSection` (UI), `CommandInvocation` (Domain, Phase 1).
- Produces: `enum SystemTab: String, CaseIterable, Identifiable, Sendable { case overview, storage, serviceLogs, about }`; `enum AppSheetIntent: Identifiable { case run(imageReference: String?), build, pull, copy(containerID: String?), export(containerID: String), console(seed: CommandInvocation?) }`; `ShellState.systemTab: SystemTab`, `ShellState.commandPalettePresented: Bool`, `ShellState.pendingSheet: AppSheetIntent?`; `ShellState.openSystem(tab:)`, `ShellState.toggleCommandPalette()`, `ShellState.present(_:)`.

- [ ] **Step 1: Write the failing test**

Create `Tests/CapsuleUnitTests/ShellNavigationTests.swift`:
```swift
//
//  ShellNavigationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleUI

@MainActor
final class ShellNavigationTests: XCTestCase {
    func testNewStateDefaults() {
        let shell = ShellState()
        XCTAssertEqual(shell.systemTab, .overview)
        XCTAssertFalse(shell.commandPalettePresented)
        XCTAssertNil(shell.pendingSheet)
    }

    func testOpenSystemDeepLinksSelectionAndTab() {
        let shell = ShellState()
        shell.openSystem(tab: .storage)
        XCTAssertEqual(shell.selection, .system)
        XCTAssertEqual(shell.systemTab, .storage)
    }

    func testToggleCommandPalette() {
        let shell = ShellState()
        shell.toggleCommandPalette()
        XCTAssertTrue(shell.commandPalettePresented)
        shell.toggleCommandPalette()
        XCTAssertFalse(shell.commandPalettePresented)
    }

    func testPresentSetsPendingSheet() {
        let shell = ShellState()
        shell.present(.build)
        XCTAssertEqual(shell.pendingSheet?.id, "build")
        shell.present(.export(containerID: "abc"))
        XCTAssertEqual(shell.pendingSheet?.id, "export-abc")
    }

    func testSystemTabIsExhaustive() {
        XCTAssertEqual(SystemTab.allCases.count, 4)
        XCTAssertEqual(SystemTab.serviceLogs.id, "serviceLogs")
    }
}
```

- [ ] **Step 2: Run it — expect FAIL.** `make test`. Expected: compile error (`SystemTab`, `AppSheetIntent`, `ShellState.systemTab/commandPalettePresented/pendingSheet`, `openSystem`/`toggleCommandPalette`/`present` undefined).

- [ ] **Step 3: Create `SystemTab`**

Create `Sources/CapsuleUI/SystemTab.swift`:
```swift
//
//  SystemTab.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

/// The sub-tabs of the always-available System surface. Mirrors the four `TabView` tabs in
/// `SystemDetailView` (Overview / Storage / Service Logs / About) so the palette and menus
/// can deep-link straight to one (`Open System Logs` → `.serviceLogs`,
/// `Reclaim Disk Space` → `.storage`).
public enum SystemTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case storage
    case serviceLogs
    case about

    public var id: String { rawValue }
}
```

- [ ] **Step 4: Create `AppSheetIntent`**

Create `Sources/CapsuleUI/AppSheetIntent.swift`:
```swift
//
//  AppSheetIntent.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain

/// A request to present one of the app-level sheets from a non-list surface (the command
/// palette or the menu bar). The list views keep their own local sheet enums; this is the
/// shared entry point routed through `ShellState.pendingSheet` and presented by
/// `AppShellView` against the existing sheet views/models.
public enum AppSheetIntent: Identifiable {
    case run(imageReference: String?)
    case build
    case pull
    case copy(containerID: String?)
    case export(containerID: String)
    case console(seed: CommandInvocation?)

    public var id: String {
        switch self {
        case let .run(imageReference): return "run-\(imageReference ?? "")"
        case .build: return "build"
        case .pull: return "pull"
        case let .copy(containerID): return "copy-\(containerID ?? "")"
        case let .export(containerID): return "export-\(containerID)"
        case .console: return "console"
        }
    }
}
```

- [ ] **Step 5: Add the state + methods to `ShellState`**

The current stored properties end at `terminalPaneHeight` and the init signature is:
```swift
    public init(
        selection: SidebarSection = .containers,
        inspectorPresented: Bool = true,
        activityPanePresented: Bool = true,
        activityTab: ActivityTab = .logs,
        activityLog: [String] = [],
        terminalSession: TerminalSessionState? = nil,
        terminalPaneHeight: Double = 320
    ) {
```
In `Sources/CapsuleUI/ShellState.swift`, add three stored properties after `public var terminalPaneHeight: Double`:
```swift
    /// Which System sub-tab is shown (deep-linked by `Open System Logs` / `Reclaim Disk Space`).
    public var systemTab: SystemTab
    /// Whether the ⌘K command palette overlay is presented.
    public var commandPalettePresented: Bool
    /// The app-level sheet to present (palette/menu path), or nil.
    public var pendingSheet: AppSheetIntent?
```
Replace the init signature + body opening with the extended version (new params last, defaulted so existing call-sites still compile):
```swift
    public init(
        selection: SidebarSection = .containers,
        inspectorPresented: Bool = true,
        activityPanePresented: Bool = true,
        activityTab: ActivityTab = .logs,
        activityLog: [String] = [],
        terminalSession: TerminalSessionState? = nil,
        terminalPaneHeight: Double = 320,
        systemTab: SystemTab = .overview,
        commandPalettePresented: Bool = false,
        pendingSheet: AppSheetIntent? = nil
    ) {
        self.selection = selection
        self.inspectorPresented = inspectorPresented
        self.activityPanePresented = activityPanePresented
        self.activityTab = activityTab
        self.activityLog = activityLog
        self.terminalSession = terminalSession
        self.terminalPaneHeight = terminalPaneHeight
        self.systemTab = systemTab
        self.commandPalettePresented = commandPalettePresented
        self.pendingSheet = pendingSheet
    }
```
Add the navigation methods after `toggleActivityPane()`:
```swift
    /// Deep-links to a System sub-tab: selects the System surface and switches its tab.
    public func openSystem(tab: SystemTab) {
        selection = .system
        systemTab = tab
    }

    /// Shows/hides the ⌘K command palette.
    public func toggleCommandPalette() { commandPalettePresented.toggle() }

    /// Requests an app-level sheet (presented by `AppShellView`).
    public func present(_ intent: AppSheetIntent) { pendingSheet = intent }
```

- [ ] **Step 6: Run it — expect PASS.** `make test`. Expected: `ShellNavigationTests` green; full suite green.

- [ ] **Step 7: Commit**
```
git add -A && git commit -m "feat(ui): add SystemTab, AppSheetIntent, and ShellState navigation state

Adds the System sub-tab deep-link, command-palette presentation flag, and
pending app-sheet intent to ShellState (defaulted init params keep existing
call-sites compiling).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw"
```

---

### Task P5.2: `FuzzyMatch` ranker (Domain)

**Files:**
- Create: `Sources/CapsuleDomain/FuzzyMatch.swift`
- Test: `Tests/CapsuleUnitTests/FuzzyMatchTests.swift`

**Interfaces:**
- Produces: `enum FuzzyMatch { static func matches(_ query: String, _ candidate: String) -> Bool; static func score(_ query: String, _ candidate: String) -> Int? }` — case-insensitive subsequence; `score` nil when no match, lower = better.

- [ ] **Step 1: Write the failing test**

Create `Tests/CapsuleUnitTests/FuzzyMatchTests.swift`:
```swift
//
//  FuzzyMatchTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class FuzzyMatchTests: XCTestCase {
    func testSubsequenceMatches() {
        XCTAssertTrue(FuzzyMatch.matches("rsi", "Run Selected Image"))
        XCTAssertTrue(FuzzyMatch.matches("", "anything"))
        XCTAssertFalse(FuzzyMatch.matches("zqx", "Run Selected Image"))
    }

    func testScoreNilWhenNoMatch() {
        XCTAssertNil(FuzzyMatch.score("xyz", "Pull Image"))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(FuzzyMatch.matches("PULL", "pull image"))
    }

    func testContiguousPrefixScoresBetterThanScattered() {
        let tight = FuzzyMatch.score("pul", "Pull Image")
        let loose = FuzzyMatch.score("pul", "Preview Ultra Long")
        XCTAssertNotNil(tight)
        XCTAssertNotNil(loose)
        if let tight, let loose { XCTAssertLessThan(tight, loose) }
    }
}
```

- [ ] **Step 2: Run it — expect FAIL.** `make test`. Expected: compile error (`FuzzyMatch` undefined).

- [ ] **Step 3: Implement `FuzzyMatch`**

Create `Sources/CapsuleDomain/FuzzyMatch.swift`:
```swift
//
//  FuzzyMatch.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. A pure,
//  case-insensitive subsequence matcher used to rank command-palette entries — kept in
//  Domain so it is unit-testable without any SwiftUI surface.

/// Case-insensitive subsequence fuzzy matching for the command palette.
public enum FuzzyMatch {
    /// Whether every character of `query` appears in `candidate`, in order.
    public static func matches(_ query: String, _ candidate: String) -> Bool {
        score(query, candidate) != nil
    }

    /// A match score (lower is better), or nil when `query` is not a subsequence of
    /// `candidate`. Earlier and more contiguous matches score lower.
    public static func score(_ query: String, _ candidate: String) -> Int? {
        let needle = Array(query.lowercased())
        guard !needle.isEmpty else { return 0 }
        let haystack = Array(candidate.lowercased())

        var qi = 0
        var total = 0
        var lastMatch = -1
        for (ci, ch) in haystack.enumerated() where qi < needle.count && ch == needle[qi] {
            // Distance from the start for the first hit; gap since the previous hit otherwise.
            total += lastMatch < 0 ? ci : (ci - lastMatch - 1)
            lastMatch = ci
            qi += 1
        }
        return qi == needle.count ? total : nil
    }
}
```

- [ ] **Step 4: Run it — expect PASS.** `make test`. Expected: `FuzzyMatchTests` green; full suite green.

- [ ] **Step 5: Commit**
```
git add -A && git commit -m "feat(domain): add FuzzyMatch subsequence ranker

Pure, case-insensitive subsequence matcher (score nil = no match, lower =
better) for ranking command-palette entries. Lives in Domain so it is
unit-testable without UI.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw"
```

---

### Task P5.3: `CommandCatalog` + `CommandContext` + `CommandAction` + `CommandShortcut`

**Files:**
- Create: `Sources/CapsuleUI/CommandCatalog.swift`
- Modify: `Sources/CapsuleDomain/ContainerLifecycleModel.swift` (add the `execInvocation(id:)` console-seed convenience, after P2.8's `execInvocation(id:command:)`)
- Modify: `Sources/CapsuleDomain/RunModel.swift` (add the `runInvocation(forImage:)` console-seed accessor, after P2.2's migrated `commandPreview`)
- Test: `Tests/CapsuleUnitTests/CommandCatalogTests.swift`

**Interfaces:**
- Consumes: `ShellState`, `ShellActions` (UI); `SystemStatusModel`, `ImageBrowserModel`, `ContainerBrowserModel`, `ContainerLifecycleModel`, `RunModel`, `BuildModel`, `PluginCatalogModel`, `SavedRunPreset`/`SavedBuildPreset` (Domain). `RunModel.runPresets`/`apply(_:)`/`reset(image:)`, `BuildModel.buildPresets`/`apply(_:)`, `ContainerLifecycleModel.openShell(id:)`, `PluginCatalogModel.plugins`/`terminalRequest(for:)`, `ShellState.present(_:)`/`openSystem(tab:)`/`toggleInspector()`/`openTerminal(_:)`, `ShellActions.recover`/`stopServices`.
- Produces: `struct CommandShortcut: Equatable { init(_ key: KeyEquivalent, modifiers: EventModifiers = .command); var display: String }`; `struct CommandAction: Identifiable { id, title, subtitle?, symbol, shortcut?, isEnabled, run }`; `@MainActor struct CommandContext`; `enum CommandCatalog { @MainActor static func actions(_ ctx: CommandContext) -> [CommandAction] }` (13 fixed + dynamic preset/plugin actions); and the Domain best-fit-seed accessors `ContainerLifecycleModel.execInvocation(id:) -> CommandInvocation` and `RunModel.runInvocation(forImage:) -> CommandInvocation` (used to seed the Command Console **live** inside the raw-command-preview action, not stored on the context).

- [ ] **Step 1: Write the failing test**

Create `Tests/CapsuleUnitTests/CommandCatalogTests.swift`:
```swift
//
//  CommandCatalogTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import CapsuleDomain
import XCTest

@testable import CapsuleUI

@MainActor
final class CommandCatalogTests: XCTestCase {
    private func makeContext(
        runPresetStore: any PresetStore = InMemoryPresetStore(),
        plugins: any PluginDiscovering = NoPluginDiscovery()
    ) -> (CommandContext, ContainerBrowserModel, ImageBrowserModel, RunModel, PluginCatalogModel) {
        let backend = MockBackend()
        let taskCenter = TaskCenter()
        let shell = ShellState()
        let containers = ContainerBrowserModel(backend: backend)
        let images = ImageBrowserModel(backend: backend)
        let run = RunModel(backend: backend, taskCenter: taskCenter, presetStore: runPresetStore)
        let build = BuildModel(backend: backend, taskCenter: taskCenter)
        let lifecycle = ContainerLifecycleModel(backend: backend)
        let system = SystemStatusModel(backend: backend)
        let pluginCatalog = PluginCatalogModel(discovering: plugins, isServiceRunning: { true })
        let actions = ShellActions(recover: { _ in }, stopServices: {})
        let ctx = CommandContext(
            shell: shell,
            systemModel: system,
            imageBrowserModel: images,
            containerBrowserModel: containers,
            lifecycleModel: lifecycle,
            runModel: run,
            buildModel: build,
            pluginCatalog: pluginCatalog,
            actions: actions,
            followLogs: {})
        return (ctx, containers, images, run, pluginCatalog)
    }

    private func enabled(_ id: String, in ctx: CommandContext) -> Bool {
        CommandCatalog.actions(ctx).first { $0.id == id }!.isEnabled
    }

    func testThirteenFixedActions() {
        let (ctx, _, _, _, _) = makeContext()
        let fixed = CommandCatalog.actions(ctx).filter {
            !$0.id.hasPrefix("preset-") && !$0.id.hasPrefix("plugin-")
        }
        XCTAssertEqual(fixed.count, 13)
        XCTAssertTrue(fixed.contains { $0.id == "raw-command-preview" })
        XCTAssertTrue(fixed.contains { $0.id == "toggle-inspector" })
    }

    func testContainerSelectionGatesActions() {
        let (ctx, containers, _, _, _) = makeContext()
        XCTAssertFalse(enabled("exec-shell", in: ctx))
        XCTAssertFalse(enabled("export-container", in: ctx))
        containers.selection = ["c1"]
        XCTAssertTrue(enabled("exec-shell", in: ctx))
        XCTAssertTrue(enabled("export-container", in: ctx))
    }

    func testImageSelectionGatesRun() {
        let (ctx, _, images, _, _) = makeContext()
        XCTAssertFalse(enabled("run-selected-image", in: ctx))
        images.selection = ["nginx:latest"]
        XCTAssertTrue(enabled("run-selected-image", in: ctx))
    }

    func testNavigationActionsAlwaysEnabled() {
        let (ctx, _, _, _, _) = makeContext()
        XCTAssertTrue(enabled("open-system-logs", in: ctx))
        XCTAssertTrue(enabled("reclaim-disk", in: ctx))
        XCTAssertTrue(enabled("toggle-inspector", in: ctx))
        XCTAssertTrue(enabled("raw-command-preview", in: ctx))
    }

    func testRunPresetSurfacesAsAction() {
        let (ctx, _, _, run, _) = makeContext()
        run.savePreset(name: "web")
        let actions = CommandCatalog.actions(ctx)
        XCTAssertTrue(actions.contains { $0.id.hasPrefix("preset-run-") })
        XCTAssertTrue(actions.contains { $0.title == "Run Preset: web" })
    }

    func testPluginSurfacesAsActionAfterRefresh() {
        let (ctx, _, _, _, pluginCatalog) = makeContext(plugins: OnePlugin())
        XCTAssertFalse(CommandCatalog.actions(ctx).contains { $0.id == "plugin-compose" })
        pluginCatalog.refresh()
        XCTAssertTrue(CommandCatalog.actions(ctx).contains { $0.id == "plugin-compose" })
    }

    func testShortcutDisplay() {
        XCTAssertEqual(CommandShortcut("r", modifiers: [.shift, .command]).display, "⇧⌘R")
        XCTAssertEqual(CommandShortcut("k", modifiers: [.shift, .command]), CommandShortcut("k", modifiers: [.shift, .command]))
    }
}

private struct OnePlugin: PluginDiscovering {
    func installedPlugins() -> [PluginInfo] {
        [PluginInfo(name: "compose", path: "/usr/local/libexec/container-plugins/container-compose")]
    }
}
```

- [ ] **Step 2: Run it — expect FAIL.** `make test`. Expected: compile error (`CommandCatalog`, `CommandContext`, `CommandAction`, `CommandShortcut` undefined).

- [ ] **Step 3: Add the console-seed Domain accessors, then implement the catalog**

First add two Domain accessors so the composition root can seed the Command Console from the
current selection WITHOUT the UI touching `CLICommand`/`RunConfiguration` directly (arch guard:
UI imports no Backend). Both live in Domain, which already imports `CapsuleBackend`.

In `Sources/CapsuleDomain/ContainerLifecycleModel.swift`, add directly after
`execInvocation(id:command:)` (added in P2.8):
```swift
    /// The `exec -it <id> sh` invocation for the current container — the Command Console's
    /// best-fit seed when a container is selected. A convenience over `execInvocation(id:command:)`.
    public func execInvocation(id: String) -> CommandInvocation {
        CommandInvocation(CLICommand.execShell(id: id, command: []))
    }
```
In `Sources/CapsuleDomain/RunModel.swift`, add directly after the migrated `commandPreview`
accessor (from P2.2):
```swift
    /// The `run <image>` invocation for a given image — the Command Console's best-fit seed
    /// when an image (but no container) is selected. Builds the argv via `RunConfiguration`
    /// so `RunConfiguration` never leaks into the UI.
    public func runInvocation(forImage image: String) -> CommandInvocation {
        CommandInvocation(RunConfiguration(image: image).arguments)
    }
```

Then create `Sources/CapsuleUI/CommandCatalog.swift`:
```swift
//
//  CommandCatalog.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The single source of truth for every power-user action. Both the ⌘K palette and the
//  menu bar render `CommandCatalog.actions(_:)`, so the two surfaces cannot drift. Pure
//  ranking lives in Domain (`FuzzyMatch`); enablement and `run` closures live here because
//  they touch UI state (`ShellState`/`ShellActions`).

import CapsuleDomain
import SwiftUI

/// A keyboard shortcut for a command action (rendered by the menu and shown in the palette).
public struct CommandShortcut: Equatable {
    public let key: KeyEquivalent
    public let modifiers: EventModifiers

    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) {
        self.key = key
        self.modifiers = modifiers
    }

    /// `KeyEquivalent` is not reliably `Equatable` across SDKs, so compare its character.
    public static func == (lhs: CommandShortcut, rhs: CommandShortcut) -> Bool {
        lhs.key.character == rhs.key.character && lhs.modifiers == rhs.modifiers
    }

    /// A glyph string like `⇧⌘R` for palette rows.
    public var display: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += String(key.character).uppercased()
        return result
    }
}

/// One command surfaced in the palette and the menu bar.
public struct CommandAction: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let symbol: String
    public let shortcut: CommandShortcut?
    public let isEnabled: Bool
    public let run: () -> Void

    public init(
        id: String,
        title: String,
        subtitle: String?,
        symbol: String,
        shortcut: CommandShortcut?,
        isEnabled: Bool,
        run: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.run = run
    }
}

/// The live app state a command needs. Built once in `AppEnvironment.live()` and threaded
/// into both `CapsuleCommands` (menus) and `CommandPaletteView` (palette).
@MainActor
public struct CommandContext {
    public var shell: ShellState
    public var systemModel: SystemStatusModel
    public var imageBrowserModel: ImageBrowserModel
    public var containerBrowserModel: ContainerBrowserModel
    public var lifecycleModel: ContainerLifecycleModel
    public var runModel: RunModel
    public var buildModel: BuildModel
    public var pluginCatalog: PluginCatalogModel
    public var actions: ShellActions
    /// Begins log capture for the selected container and reveals the logs surface.
    public var followLogs: () -> Void

    public init(
        shell: ShellState,
        systemModel: SystemStatusModel,
        imageBrowserModel: ImageBrowserModel,
        containerBrowserModel: ContainerBrowserModel,
        lifecycleModel: ContainerLifecycleModel,
        runModel: RunModel,
        buildModel: BuildModel,
        pluginCatalog: PluginCatalogModel,
        actions: ShellActions,
        followLogs: @escaping () -> Void
    ) {
        self.shell = shell
        self.systemModel = systemModel
        self.imageBrowserModel = imageBrowserModel
        self.containerBrowserModel = containerBrowserModel
        self.lifecycleModel = lifecycleModel
        self.runModel = runModel
        self.buildModel = buildModel
        self.pluginCatalog = pluginCatalog
        self.actions = actions
        self.followLogs = followLogs
    }
}

/// Builds every command from the live context: 13 fixed actions, then dynamic Run/Build
/// presets, then discovered plugins. Selection-needing actions are disabled with a hint.
public enum CommandCatalog {
    @MainActor
    public static func actions(_ ctx: CommandContext) -> [CommandAction] {
        let shell = ctx.shell
        let hasImage = !ctx.imageBrowserModel.selection.isEmpty
        let hasContainer = !ctx.containerBrowserModel.selection.isEmpty
        let running = ctx.systemModel.health.isRunning

        var actions: [CommandAction] = [
            CommandAction(
                id: "run-selected-image", title: "Run Selected Image…",
                subtitle: hasImage ? nil : "Select an image first",
                symbol: "play.rectangle",
                shortcut: CommandShortcut("r", modifiers: [.shift, .command]),
                isEnabled: hasImage,
                run: {
                    let reference = ctx.imageBrowserModel.selectedImages.first?.reference
                    ctx.runModel.reset(image: reference ?? "")
                    shell.present(.run(imageReference: reference))
                }),
            CommandAction(
                id: "exec-shell", title: "Exec Shell in Container",
                subtitle: hasContainer ? nil : "Select a container first",
                symbol: "terminal", shortcut: nil, isEnabled: hasContainer,
                run: {
                    if let id = ctx.containerBrowserModel.selection.first {
                        ctx.lifecycleModel.openShell(id: id)
                    }
                }),
            CommandAction(
                id: "follow-logs", title: "Follow Logs", subtitle: nil,
                symbol: "text.alignleft", shortcut: nil, isEnabled: true,
                run: { ctx.followLogs() }),
            CommandAction(
                id: "build-folder", title: "Build from Folder…", subtitle: nil,
                symbol: "hammer",
                shortcut: CommandShortcut("b", modifiers: [.shift, .command]),
                isEnabled: true, run: { shell.present(.build) }),
            CommandAction(
                id: "pull-image", title: "Pull Image…", subtitle: nil,
                symbol: "arrow.down.circle",
                shortcut: CommandShortcut("p", modifiers: [.shift, .command]),
                isEnabled: true, run: { shell.present(.pull) }),
            CommandAction(
                id: "copy-to-container", title: "Copy File to Container…", subtitle: nil,
                symbol: "doc.on.doc", shortcut: nil, isEnabled: true,
                run: { shell.present(.copy(containerID: ctx.containerBrowserModel.selection.first)) }),
            CommandAction(
                id: "export-container", title: "Export Container…",
                subtitle: hasContainer ? nil : "Select a container first",
                symbol: "square.and.arrow.up", shortcut: nil, isEnabled: hasContainer,
                run: {
                    if let id = ctx.containerBrowserModel.selection.first {
                        shell.present(.export(containerID: id))
                    }
                }),
            CommandAction(
                id: "start-services", title: "Start Services", subtitle: nil,
                symbol: "play.fill", shortcut: nil, isEnabled: !running,
                run: { ctx.actions.recover(.startServices) }),
            CommandAction(
                id: "stop-services", title: "Stop Services", subtitle: nil,
                symbol: "stop.fill", shortcut: nil, isEnabled: running,
                run: { ctx.actions.stopServices() }),
            CommandAction(
                id: "open-system-logs", title: "Open System Logs", subtitle: nil,
                symbol: "doc.text.magnifyingglass", shortcut: nil, isEnabled: true,
                run: { shell.openSystem(tab: .serviceLogs) }),
            CommandAction(
                id: "reclaim-disk", title: "Reclaim Disk Space", subtitle: nil,
                symbol: "internaldrive", shortcut: nil, isEnabled: true,
                run: { shell.openSystem(tab: .storage) }),
            CommandAction(
                id: "toggle-inspector", title: "Toggle Inspector", subtitle: nil,
                symbol: "sidebar.right", shortcut: nil, isEnabled: true,
                run: { shell.toggleInspector() }),
            CommandAction(
                id: "raw-command-preview", title: "Open Raw Command Preview", subtitle: nil,
                symbol: "chevron.left.forwardslash.chevron.right",
                shortcut: CommandShortcut("k", modifiers: [.shift, .command]),
                isEnabled: true,
                run: {
                    // Best-fit seed computed LIVE at invocation (not a snapshot): the selected
                    // container's exec shell wins, else the selected image's run, else empty.
                    // Reads the context's live @Observable model references.
                    let seed: CommandInvocation? = ctx.containerBrowserModel.selection.first
                        .map { ctx.lifecycleModel.execInvocation(id: $0) }
                        ?? ctx.imageBrowserModel.selectedImages.first
                        .map { ctx.runModel.runInvocation(forImage: $0.reference) }
                    shell.present(.console(seed: seed))
                }),
        ]

        for preset in ctx.runModel.runPresets {
            actions.append(
                CommandAction(
                    id: "preset-run-\(preset.id.uuidString)",
                    title: "Run Preset: \(preset.name)", subtitle: nil,
                    symbol: "play.rectangle.on.rectangle", shortcut: nil, isEnabled: true,
                    run: {
                        ctx.runModel.apply(preset)
                        shell.present(.run(imageReference: nil))
                    }))
        }
        for preset in ctx.buildModel.buildPresets {
            actions.append(
                CommandAction(
                    id: "preset-build-\(preset.id.uuidString)",
                    title: "Build Preset: \(preset.name)", subtitle: nil,
                    symbol: "hammer.circle", shortcut: nil, isEnabled: true,
                    run: {
                        ctx.buildModel.apply(preset)
                        shell.present(.build)
                    }))
        }
        for plugin in ctx.pluginCatalog.plugins {
            actions.append(
                CommandAction(
                    id: "plugin-\(plugin.name)", title: "Plugin: \(plugin.name)",
                    subtitle: plugin.path, symbol: "puzzlepiece.extension", shortcut: nil,
                    isEnabled: true,
                    run: { shell.openTerminal(ctx.pluginCatalog.terminalRequest(for: plugin)) }))
        }
        return actions
    }
}
```

- [ ] **Step 4: Run it — expect PASS.** `make test`. Expected: `CommandCatalogTests` green; full suite green.

- [ ] **Step 5: Commit**
```
git add -A && git commit -m "feat(ui): add CommandCatalog single source of truth

CommandCatalog.actions(_:) builds the 13 fixed power-user actions plus dynamic
Run/Build preset and discovered-plugin actions from a live CommandContext.
Selection-needing actions disable with a hint subtitle. CommandShortcut and
CommandAction back both the palette and the menu bar.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw"
```

---

### Task P5.4: `CommandPaletteView` (⌘K overlay) + ranking

**Files:**
- Create: `Sources/CapsuleUI/CommandPaletteView.swift`
- Test: `Tests/CapsuleUnitTests/CommandPaletteViewTests.swift`

**Interfaces:**
- Consumes: `FuzzyMatch` (Domain); `CommandAction`, `CommandContext`, `CommandCatalog`, `ShellState` (UI).
- Produces: `struct CommandPaletteView: View { init(shell: ShellState, context: CommandContext); static func ranked(_ actions: [CommandAction], query: String) -> [CommandAction] }`.

- [ ] **Step 1: Write the failing test**

Create `Tests/CapsuleUnitTests/CommandPaletteViewTests.swift`:
```swift
//
//  CommandPaletteViewTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleUI

@MainActor
final class CommandPaletteViewTests: XCTestCase {
    private func action(_ id: String, _ title: String) -> CommandAction {
        CommandAction(
            id: id, title: title, subtitle: nil, symbol: "", shortcut: nil,
            isEnabled: true, run: {})
    }

    func testRankedEmptyQueryReturnsAllInOrder() {
        let all = [action("1", "Run"), action("2", "Build")]
        XCTAssertEqual(CommandPaletteView.ranked(all, query: "").map(\.id), ["1", "2"])
    }

    func testRankedFiltersNonMatches() {
        let all = [
            action("1", "Run Selected Image"),
            action("2", "Pull Image"),
            action("3", "Build from Folder"),
        ]
        let result = CommandPaletteView.ranked(all, query: "image")
        XCTAssertEqual(Set(result.map(\.id)), ["1", "2"])
    }

    func testRankedFirstIsBestMatch() {
        let all = [action("1", "Reclaim Disk Space"), action("2", "Run")]
        XCTAssertEqual(CommandPaletteView.ranked(all, query: "run").first?.id, "2")
    }
}
```

- [ ] **Step 2: Run it — expect FAIL.** `make test`. Expected: compile error (`CommandPaletteView` undefined).

- [ ] **Step 3: Implement the palette**

Create `Sources/CapsuleUI/CommandPaletteView.swift`:
```swift
//
//  CommandPaletteView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The ⌘K command palette: a search field over the fuzzy-ranked CommandCatalog. Return runs
//  the first enabled match; selecting a row runs it and dismisses. Renders the exact same
//  actions the menu bar does, so the two surfaces cannot drift.

import CapsuleDomain
import SwiftUI

public struct CommandPaletteView: View {
    @Bindable private var shell: ShellState
    private let context: CommandContext
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    public init(shell: ShellState, context: CommandContext) {
        self.shell = shell
        self.context = context
    }

    /// Pure filter+rank used by the body (and unit-tested in isolation).
    public static func ranked(_ actions: [CommandAction], query: String) -> [CommandAction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return actions }
        return
            actions
            .enumerated()
            .compactMap { index, action -> (Int, CommandAction, Int)? in
                guard let score = FuzzyMatch.score(trimmed, action.title) else { return nil }
                return (index, action, score)
            }
            .sorted { $0.2 != $1.2 ? $0.2 < $1.2 : $0.0 < $1.0 }
            .map(\.1)
    }

    private var matches: [CommandAction] {
        CommandPaletteView.ranked(CommandCatalog.actions(context), query: query)
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextField("Run a command…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(16)
                .focused($searchFocused)
                .onSubmit(runFirst)

            Divider()

            List(matches) { action in
                Button { run(action) } label: {
                    CommandPaletteRow(action: action)
                }
                .buttonStyle(.plain)
                .disabled(!action.isEnabled)
            }
            .listStyle(.plain)
        }
        .frame(width: 560, height: 420)
        .onAppear { searchFocused = true }
    }

    private func runFirst() {
        if let first = matches.first(where: { $0.isEnabled }) { run(first) }
    }

    private func run(_ action: CommandAction) {
        shell.commandPalettePresented = false
        action.run()
    }
}

/// One palette row: symbol, title, optional hint subtitle, and a trailing shortcut glyph.
private struct CommandPaletteRow: View {
    let action: CommandAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.symbol)
                .frame(width: 20)
                .foregroundStyle(action.isEnabled ? .primary : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .foregroundStyle(action.isEnabled ? .primary : .secondary)
                if let subtitle = action.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let shortcut = action.shortcut {
                Text(shortcut.display)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 4: Run it — expect PASS.** `make test`. Expected: `CommandPaletteViewTests` green; full suite green.

- [ ] **Step 5: Commit**
```
git add -A && git commit -m "feat(ui): add CommandPaletteView (Cmd-K overlay)

A search field over the fuzzy-ranked CommandCatalog; Return runs the first
enabled match, a row tap runs and dismisses. Static ranked(_:query:) is the
pure, unit-tested filter seam.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw"
```

---

### Task P5.5: Bind `SystemDetailView` `TabView` to `shell.systemTab`

**Files:**
- Modify: `Sources/CapsuleUI/SystemDetailView.swift:13-34` (add `@Binding selection`, drive `TabView`)
- Modify: `Sources/CapsuleUI/ContentColumnView.swift:14-46` (thread `systemTab` binding into `SystemDetailView`)
- Modify: `Sources/CapsuleUI/AppShellView.swift:171-193` (pass `systemTab: $shell.systemTab`)

**Interfaces:**
- Consumes: `ShellState.systemTab` (P5.1), `SystemTab` (P5.1).
- Produces: `SystemDetailView` selection bound to `shell.systemTab` (so `openSystem(tab:)` lands on the right sub-pane). No new public symbols.

- [ ] **Step 1: Thread the binding from the call sites (compiler red)**

In `Sources/CapsuleUI/ContentColumnView.swift`, add a stored binding after `let section: SidebarSection`:
```swift
    let section: SidebarSection
    @Binding var systemTab: SystemTab
```
and update the `SystemDetailView` construction in `body`:
```swift
            if section == .system {
                SystemDetailView(
                    health: health, actions: actions,
                    selection: $systemTab,
                    storageModel: storageModel,
                    serviceLogsModel: serviceLogsModel,
                    aboutModel: aboutModel)
            } else if health.isRunning {
```
In `Sources/CapsuleUI/AppShellView.swift`, the current `ContentColumnView(...)` call starts `ContentColumnView(\n                section: shell.selection,`. Insert the binding right after `section:`:
```swift
            ContentColumnView(
                section: shell.selection,
                systemTab: $shell.systemTab,
                health: systemModel.health,
                actions: actions,
```

- [ ] **Step 2: Run it — expect FAIL.** `make test`. Expected: compile error (`SystemDetailView` has no `selection:` parameter).

- [ ] **Step 3: Add the binding + tags to `SystemDetailView`**

In `Sources/CapsuleUI/SystemDetailView.swift`, add the binding to the stored properties:
```swift
struct SystemDetailView: View {
    let health: SystemHealth
    let actions: ShellActions
    @Binding var selection: SystemTab
    let storageModel: StorageDashboardModel
    let serviceLogsModel: LogsModel
    let aboutModel: AboutModel
```
and drive the `TabView` from it (replace the `TabView { … }` block):
```swift
    var body: some View {
        TabView(selection: $selection) {
            overview
                .tabItem { Label("Overview", systemImage: "heart.text.square") }
                .tag(SystemTab.overview)
            StorageDashboardView(model: storageModel)
                .tabItem { Label("Storage", systemImage: "internaldrive") }
                .tag(SystemTab.storage)
            ServiceLogsView(model: serviceLogsModel, isRunning: health.isRunning)
                .tabItem { Label("Service Logs", systemImage: "doc.text.magnifyingglass") }
                .tag(SystemTab.serviceLogs)
            AboutDiagnosticsView(
                model: aboutModel,
                onExportDiagnostics: { actions.recover(.exportDiagnostics) }
            )
            .tabItem { Label("About", systemImage: "info.circle") }
            .tag(SystemTab.about)
        }
    }
```

- [ ] **Step 4: Run it — expect PASS.** `make test`. Expected: build + full suite green (the `ShellNavigationTests.testOpenSystemDeepLinks…` from P5.1 covers the behavior; this task wires the view to it).

- [ ] **Step 5: Commit**
```
git add -A && git commit -m "feat(ui): bind SystemDetailView tabs to shell.systemTab

The System surface TabView now reads/writes shell.systemTab, so Open System
Logs / Reclaim Disk Space deep-link straight to the Service Logs / Storage
sub-panes instead of just reaching .system generically.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw"
```

---

### Task P5.6: Build `CommandContext` + `PluginCatalogModel` in `AppEnvironment.live()`

**Files:**
- Modify: `Sources/CapsuleApp/AppEnvironment.swift:25-116` (add `commandContext` stored property + init param)
- Modify: `Sources/CapsuleApp/AppEnvironment.swift:286-321` (construct `pluginCatalog` + `commandContext`, pass into `AppEnvironment(...)`)
- Test: `Tests/CapsuleUnitTests/AppEnvironmentCommandContextTests.swift`

**Interfaces:**
- Consumes: `PluginCatalogModel(discovering:isServiceRunning:)` (Domain, Phase 4), `LibexecPluginScanner()` (CapsuleApp, Phase 4), `CommandContext` (P5.3), `LogsModel.start(id:)`, `ShellState.revealLogs()`.
- Produces: `AppEnvironment.commandContext: CommandContext`.

- [ ] **Step 1: Write the failing test**

Create `Tests/CapsuleUnitTests/AppEnvironmentCommandContextTests.swift`:
```swift
//
//  AppEnvironmentCommandContextTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleApp
import CapsuleUI
import XCTest

@MainActor
final class AppEnvironmentCommandContextTests: XCTestCase {
    func testLiveEnvironmentExposesCommandCatalog() {
        let env = AppEnvironment.live()
        let ids = CommandCatalog.actions(env.commandContext).map(\.id)
        XCTAssertTrue(ids.contains("toggle-inspector"))
        XCTAssertTrue(ids.contains("raw-command-preview"))
        XCTAssertTrue(ids.contains("open-system-logs"))
    }
}
```

- [ ] **Step 2: Run it — expect FAIL.** `make test`. Expected: compile error (`AppEnvironment` has no member `commandContext`).

- [ ] **Step 3: Add the stored property + init param**

In `Sources/CapsuleApp/AppEnvironment.swift`, add the property after `public var terminalSurfaceProvider: any TerminalSurfaceProviding`:
```swift
    public var terminalSurfaceProvider: any TerminalSurfaceProviding
    public var commandContext: CommandContext
```
add the init parameter after `terminalSurfaceProvider: ... = StubTerminalSurfaceProvider()`:
```swift
        terminalSurfaceProvider: any TerminalSurfaceProviding = StubTerminalSurfaceProvider(),
        commandContext: CommandContext
    ) {
```
and the assignment after `self.terminalSurfaceProvider = terminalSurfaceProvider`:
```swift
        self.terminalSurfaceProvider = terminalSurfaceProvider
        self.commandContext = commandContext
```

- [ ] **Step 4: Construct `pluginCatalog` + `commandContext` in `live()`**

The current tail of `live()` reads `let actions = makeActions(systemModel: systemModel, shell: shell)` immediately before `return AppEnvironment(`. Insert the catalog + context construction between them:
```swift
        let actions = makeActions(systemModel: systemModel, shell: shell)
        let pluginCatalog = PluginCatalogModel(
            discovering: LibexecPluginScanner(),
            isServiceRunning: { systemModel.health.isRunning })
        let commandContext = CommandContext(
            shell: shell,
            systemModel: systemModel,
            imageBrowserModel: imageBrowserModel,
            containerBrowserModel: browserModel,
            lifecycleModel: lifecycleModel,
            runModel: runModel,
            buildModel: buildModel,
            pluginCatalog: pluginCatalog,
            actions: actions,
            followLogs: {
                if let id = browserModel.selection.first { logsModel.start(id: id) }
                shell.revealLogs()
            })
        return AppEnvironment(
```
and add `commandContext` to the `AppEnvironment(...)` argument list, after `terminalSurfaceProvider: terminalSurfaceProvider`:
```swift
            terminalSurfaceProvider: terminalSurfaceProvider,
            commandContext: commandContext
        )
```

- [ ] **Step 5: Run it — expect PASS.** `make test`. Expected: `AppEnvironmentCommandContextTests` green; full suite green.

- [ ] **Step 6: Commit**
```
git add -A && git commit -m "feat(app): build CommandContext + PluginCatalogModel in live()

The composition root now constructs the plugin catalog (LibexecPluginScanner,
gated on the service running) and the CommandContext that backs both the palette
and the menu bar, and exposes it on AppEnvironment.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw"
```

---

### Task P5.7: Present the palette, app-sheets, and console in `AppShellView`

**Files:**
- Modify: `Sources/CapsuleUI/AppShellView.swift` (add `import AppKit`, `commandContext` property+init param, two `.sheet` modifiers, `pendingSheetView`/`exportSheet` helpers)
- Modify: `Sources/CapsuleUI/RootView.swift` (thread `commandContext` through to `AppShellView`)
- Modify: `Sources/CapsuleApp/CapsuleScene.swift` (store + pass `environment.commandContext` to `RootView`)

**Interfaces:**
- Consumes: `CommandContext` (P5.3), `CommandPaletteView` (P5.4), `AppSheetIntent` (P5.1), `CommandConsoleView(seed:onRunEmbedded:onRunExternal:onClose:)` (Phase 4), `QuickRunSheet`, `BuildSheet`, `PullImageSheet`, `CopySheet`, `ImageActionsModel.pull(reference:platform:)`/`retryTask(_:)`, `CopyModel.reset(containerID:)`, `ContainerLifecycleModel.export(id:to:)`/`openInExternalTerminal(_:)`, `ShellState.openTerminal(_:)`.
- Produces: app-level sheet presentation (`$shell.pendingSheet`) + palette presentation (`$shell.commandPalettePresented`).

- [ ] **Step 1: Thread `commandContext` from `CapsuleScene` (compiler red)**

In `Sources/CapsuleApp/CapsuleScene.swift`, add a stored property after `private let terminalSurfaceProvider: any TerminalSurfaceProviding`:
```swift
    private let terminalSurfaceProvider: any TerminalSurfaceProviding
    private let commandContext: CommandContext
```
and the assignment in `init(environment:)` after `self.terminalSurfaceProvider = environment.terminalSurfaceProvider`:
```swift
        self.terminalSurfaceProvider = environment.terminalSurfaceProvider
        self.commandContext = environment.commandContext
```
In the `RootView(...)` construction inside `body`, add `commandContext` after `terminalSurfaceProvider: terminalSurfaceProvider`:
```swift
                actions: actions,
                terminalSurfaceProvider: terminalSurfaceProvider,
                commandContext: commandContext
            )
```

- [ ] **Step 2: Run it — expect FAIL.** `make test`. Expected: compile error (`RootView` has no `commandContext:` parameter).

- [ ] **Step 3: Thread `commandContext` through `RootView`**

In `Sources/CapsuleUI/RootView.swift`, add the stored property after `private let terminalSurfaceProvider: any TerminalSurfaceProviding`:
```swift
    private let terminalSurfaceProvider: any TerminalSurfaceProviding
    private let commandContext: CommandContext
```
add the init parameter after `terminalSurfaceProvider: ... = StubTerminalSurfaceProvider()`:
```swift
        terminalSurfaceProvider: any TerminalSurfaceProviding = StubTerminalSurfaceProvider(),
        commandContext: CommandContext
    ) {
```
the assignment after `self.terminalSurfaceProvider = terminalSurfaceProvider`:
```swift
        self.terminalSurfaceProvider = terminalSurfaceProvider
        self.commandContext = commandContext
```
and pass it into `AppShellView(...)` in `body`, after `terminalSurfaceProvider: terminalSurfaceProvider`:
```swift
            actions: actions,
            terminalSurfaceProvider: terminalSurfaceProvider,
            commandContext: commandContext
        )
```

- [ ] **Step 4: Accept + present in `AppShellView`**

In `Sources/CapsuleUI/AppShellView.swift`, add `import AppKit` under `import CapsuleDomain`:
```swift
import AppKit
import CapsuleDomain
import SwiftUI
```
add the stored property after `let terminalSurfaceProvider: any TerminalSurfaceProviding`:
```swift
    let terminalSurfaceProvider: any TerminalSurfaceProviding
    let commandContext: CommandContext
```
add the init parameter after `terminalSurfaceProvider: ... = StubTerminalSurfaceProvider()`:
```swift
        terminalSurfaceProvider: any TerminalSurfaceProviding = StubTerminalSurfaceProvider(),
        commandContext: CommandContext
    ) {
```
the assignment after `self.terminalSurfaceProvider = terminalSurfaceProvider`:
```swift
        self.terminalSurfaceProvider = terminalSurfaceProvider
        self.commandContext = commandContext
```
Replace the `body` so the split view also refreshes plugins and hosts the two app-level sheets:
```swift
    public var body: some View {
        NavigationSplitView {
            SidebarView(
                shell: shell,
                availableFeatures: systemModel.health.availableFeatures,
                bannerKind: systemModel.health.bannerKind,
                statusLabel: systemModel.health.statusLabel
            )
        } detail: {
            detailColumn
        }
        .task {
            await systemModel.refreshStatus()
            commandContext.pluginCatalog.refresh()
        }
        .sheet(isPresented: $shell.commandPalettePresented) {
            CommandPaletteView(shell: shell, context: commandContext)
        }
        .sheet(item: $shell.pendingSheet) { intent in
            pendingSheetView(intent)
        }
    }
```
Add the sheet builders at the end of the struct (before the closing brace):
```swift
    /// Presents the app-level sheets requested from the palette/menus, reusing the same sheet
    /// views/models the list surfaces use. The caller (the catalog action) preps the model
    /// (e.g. `runModel.reset` / `runModel.apply`) before setting `shell.pendingSheet`.
    @ViewBuilder
    private func pendingSheetView(_ intent: AppSheetIntent) -> some View {
        switch intent {
        case .run:
            QuickRunSheet(
                model: runModel,
                onResolveImage: { _ in shell.present(.pull) },
                onClose: { shell.pendingSheet = nil })
        case .build:
            BuildSheet(model: buildModel, onClose: { shell.pendingSheet = nil })
        case .pull:
            PullImageSheet(
                initialReference: "",
                onPull: { reference, platform in
                    imageActionsModel.pull(reference: reference, platform: platform)
                },
                onRetry: { imageActionsModel.retryTask($0) },
                onClose: { shell.pendingSheet = nil },
                invocationFor: { ref, platform in
                    imageActionsModel.pullInvocation(reference: ref, platform: platform)
                })
        case let .copy(containerID):
            CopySheet(model: copyModel, onClose: { shell.pendingSheet = nil })
                .onAppear { copyModel.reset(containerID: containerID ?? "") }
        case let .export(containerID):
            exportSheet(containerID: containerID)
        case let .console(seed):
            CommandConsoleView(
                seed: seed,
                onRunEmbedded: { request in shell.openTerminal(request) },
                onRunExternal: { argv in lifecycleModel.openInExternalTerminal(argv) },
                onClose: { shell.pendingSheet = nil })
        }
    }

    /// A minimal export prompt: a Save panel feeds `lifecycleModel.export(id:to:)`.
    private func exportSheet(containerID: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Container").font(.headline)
            Text("Export “\(containerID)” to a tar archive on disk.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { shell.pendingSheet = nil }
                Button("Choose File…") {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "\(containerID).tar"
                    panel.canCreateDirectories = true
                    panel.title = "Export Container"
                    let response = panel.runModal()
                    shell.pendingSheet = nil
                    if response == .OK, let url = panel.url {
                        Task { await lifecycleModel.export(id: containerID, to: url) }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
```

- [ ] **Step 5: Run it — expect PASS.** `make test`. Expected: build + full suite green.

- [ ] **Step 6: Commit**
```
git add -A && git commit -m "feat(ui): present command palette, app-sheets, and console in AppShellView

Threads CommandContext from CapsuleScene through RootView into AppShellView,
which now hosts the Cmd-K palette (.sheet on shell.commandPalettePresented) and
the shared app-level sheets (.sheet on shell.pendingSheet) — Run/Build/Pull/Copy
reuse the existing sheet views, Export drives a Save panel, and Console escalates
to the embedded/external terminal. Plugins refresh after each status read.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw"
```

---

### Task P5.8: Render menus from the catalog + enable ⌘K in `CapsuleCommands`

**Files:**
- Modify: `Sources/CapsuleApp/CapsuleCommands.swift:20-104` (add `commandContext` param; add `Commands`/`Presets` menus; enable the reserved ⌘K item)
- Modify: `Sources/CapsuleApp/CapsuleScene.swift:114-122` (pass `commandContext` into `CapsuleCommands`)

**Interfaces:**
- Consumes: `CommandContext` (P5.3), `CommandCatalog.actions(_:)` (P5.3), `CommandAction`/`CommandShortcut` (P5.3), `ShellState.toggleCommandPalette()` (P5.1).
- Produces: a `Commands` menu (all fixed catalog actions) and a `Presets` menu (dynamic preset/plugin actions) that render from the same catalog as the palette; an enabled ⌘K item.

- [ ] **Step 1: Pass `commandContext` from `CapsuleScene` (compiler red)**

In `Sources/CapsuleApp/CapsuleScene.swift`, the current `.commands { CapsuleCommands(...) }` block is:
```swift
        .commands {
            CapsuleCommands(
                updater: updater,
                shell: shell,
                systemModel: systemModel,
                actions: actions,
                machineActionsModel: machineActionsModel
            )
        }
```
Add `commandContext` as the final argument:
```swift
        .commands {
            CapsuleCommands(
                updater: updater,
                shell: shell,
                systemModel: systemModel,
                actions: actions,
                machineActionsModel: machineActionsModel,
                commandContext: commandContext
            )
        }
```

- [ ] **Step 2: Run it — expect FAIL.** `make test`. Expected: compile error (`CapsuleCommands` has no `commandContext:` parameter).

- [ ] **Step 3: Accept the context, render menus, enable ⌘K**

In `Sources/CapsuleApp/CapsuleCommands.swift`, add the stored property after `private let machineActionsModel: MachineActionsModel`:
```swift
    private let machineActionsModel: MachineActionsModel
    private let commandContext: CommandContext
```
add the init parameter after `machineActionsModel: MachineActionsModel` and its assignment:
```swift
        machineActionsModel: MachineActionsModel,
        commandContext: CommandContext
    ) {
        self.updater = updater
        self.shell = shell
        self.systemModel = systemModel
        self.actions = actions
        self.machineActionsModel = machineActionsModel
        self.commandContext = commandContext
    }
```
Replace the reserved `Command Palette…` button (currently disabled) in the Resource menu so ⌘K toggles the palette:
```swift
            Divider()

            Button("Command Palette…") { shell.toggleCommandPalette() }
                .keyboardShortcut("k", modifiers: [.command])
        }
```
Add the two new menus immediately after the `CommandMenu("Resource") { … }` block (still inside `body`):
```swift
        // Commands — every fixed catalog action, rendered from the same source the palette uses.
        CommandMenu("Commands") {
            ForEach(fixedActions) { menuButton($0) }
        }

        // Presets — dynamic Run/Build presets and discovered plugins.
        CommandMenu("Presets") {
            if dynamicActions.isEmpty {
                Button("No Presets or Plugins") {}.disabled(true)
            } else {
                ForEach(dynamicActions) { menuButton($0) }
            }
        }
    }
```
Add the catalog-partition helpers + the row builder after `body` (before the closing brace of the struct):
```swift
    @MainActor
    private var catalogActions: [CommandAction] { CommandCatalog.actions(commandContext) }

    @MainActor
    private var fixedActions: [CommandAction] {
        catalogActions.filter { !$0.id.hasPrefix("preset-") && !$0.id.hasPrefix("plugin-") }
    }

    @MainActor
    private var dynamicActions: [CommandAction] {
        catalogActions.filter { $0.id.hasPrefix("preset-") || $0.id.hasPrefix("plugin-") }
    }

    @ViewBuilder
    private func menuButton(_ action: CommandAction) -> some View {
        let button = Button(action.title) { action.run() }
            .disabled(!action.isEnabled)
        if let shortcut = action.shortcut {
            button.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            button
        }
    }
```

- [ ] **Step 4: Run it — expect PASS.** `make test`. Expected: build + full suite green. Manually confirm no shortcut collides with the live set (⌥⌘I, ⌘J, ⇧⌘L, ⌘R, ⌘K, ⌘,) — only `run-selected-image`/`build-folder`/`pull-image`/`raw-command-preview` carry shortcuts (⇧⌘R/⇧⌘B/⇧⌘P/⇧⌘K).

- [ ] **Step 5: Commit**
```
git add -A && git commit -m "feat(app): render menu bar from CommandCatalog + enable Cmd-K

CapsuleCommands now takes the CommandContext, renders a Commands menu (all 13
fixed actions) and a Presets menu (dynamic Run/Build presets + plugins) from the
same CommandCatalog the palette uses, and the reserved Cmd-K item now toggles the
palette. New shortcuts stay clear of the live set.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw"
```

# Phase 6 — Integration, architecture guard, review & GUI smoke

Phase 6 closes the milestone with verification only — it adds no product code. It locks the Phase 1 relocation behind a gated real-CLI argv probe and behind always-on architecture-guard assertions, adds an always-on `LibexecPluginScanner` probe, then runs a whole-branch 3-lens adversarial review and a live interactive GUI smoke of the headline power-user flows. Every test here either skips cleanly (gated) or runs unconditionally; when they all pass and the smoke checklist is clean the branch is ready for `superpowers:finishing-a-development-branch`.

### Task P6.1: Gated argv-shape probe for the relocated argv factory

**Files:**
- Modify: `Tests/CapsuleIntegrationTests/CLIBackendIntegrationTests.swift` (append a `// MARK: - M11` section with a `runContainer` helper + the gated probe, before the final `}` at `:127`)

**Interfaces:**
- Consumes: `CLICommand.listContainers(all: Bool) -> [String]`, `CLICommand.listImages() -> [String]`, `CLICommand.systemDiskUsage() -> [String]` — all relocated to `CapsuleBackend` in Phase 1; the test file already declares `import CapsuleBackend`. Also `requireIntegration() throws` (the existing single skip gate).
- Produces: gated test `testRelocatedCLICommandYieldsRealCLIValidArgv()`; private helper `runContainer(_ arguments: [String]) throws -> (status: Int32, output: String)`.

- [ ] **Step 1: Write the gated argv-shape probe.** Insert immediately before the closing brace of `CLIBackendIntegrationTests` (after `testListDNSDomainsAgainstRealCLI`). The probe runs only read-only argv (`list`, `image list`, `system df`) — no host mutation — and asserts the real CLI does not reject the shape the *relocated* `CLICommand` emits. It deliberately does **not** require exit 0, so a stopped service never false-fails; only a renamed flag / wrong subcommand path (which makes the CLI print usage) fails it.
```swift
    // MARK: - M11: relocated argv factory (CLICommand now lives in CapsuleBackend)

    /// Runs `container <arguments>` via the user's PATH and returns the status plus the
    /// combined stdout+stderr. Read EOF before `waitUntilExit()` to avoid a pipe-buffer
    /// deadlock on larger output.
    private func runContainer(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["container"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// The relocated `CLICommand` must still emit flags / subcommand paths the real CLI
    /// accepts. Only read-only argv is probed (no host mutation); service state is irrelevant
    /// because we assert on argv-shape rejection, not exit code.
    func testRelocatedCLICommandYieldsRealCLIValidArgv() throws {
        try requireIntegration()
        let probes: [[String]] = [
            CLICommand.listContainers(all: true),  // ["list", "--all", "--format", "json"]
            CLICommand.listImages(),               // ["image", "list", "--format", "json"]
            CLICommand.systemDiskUsage(),          // ["system", "df", "--format", "json"]
        ]
        for argv in probes {
            let result = try runContainer(argv)
            XCTAssertFalse(
                result.output.contains("Usage:"),
                "real CLI rejected the relocated argv shape \(argv): \(result.output)"
            )
            XCTAssertFalse(
                result.output.localizedCaseInsensitiveContains("unexpected argument"),
                "real CLI saw an unexpected argument in \(argv): \(result.output)"
            )
            XCTAssertFalse(
                result.output.localizedCaseInsensitiveContains("unknown option"),
                "real CLI saw an unknown option in \(argv): \(result.output)"
            )
        }
    }
```

- [ ] **Step 2: Run gated — expect PASS.** Run `CAPSULE_INTEGRATION=1 make test`. Expect `testRelocatedCLICommandYieldsRealCLIValidArgv` to execute against the real `container` binary and pass. (If Phase 1 had renamed a flag or broken a subcommand path during the move, the CLI prints `Usage:` and this fails — that is the regression it guards.)

- [ ] **Step 3: Run default — confirm clean skip.** Run `make test`. Expect the new probe to report **skipped** (alongside `testGuardSkipsCleanlyWithoutEnv`) and the full unit suite green, proving the gate keeps flag-unset CI clean.

- [ ] **Step 4: Commit.**
```
test(integration): relocated CLICommand yields real-CLI-valid argv

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

### Task P6.2: Always-on plugin-scanner probe against the real libexec dirs

**Files:**
- Modify: `Tests/CapsuleIntegrationTests/CLIBackendIntegrationTests.swift` (add `import CapsuleApp` + `import CapsuleDomain`; append an always-on scanner test)
- Modify: `Package.swift:116` (add `"CapsuleApp"` to the `CapsuleIntegrationTests` target dependencies)

**Interfaces:**
- Consumes: `LibexecPluginScanner.init(directories: [String] = ["/usr/local/libexec/container-plugins", "/usr/local/libexec/container/plugins"], fileManager: FileManager = .default)` and `func installedPlugins() -> [PluginInfo]` (Phase 4, `CapsuleApp`); `PluginInfo { var name: String; var path: String; var id: String { name } }` (Phase 4, `CapsuleDomain`).
- Produces: always-on test `testLibexecPluginScannerRunsCleanlyAgainstRealDirs()`; a new package edge `CapsuleIntegrationTests → CapsuleApp`.

- [ ] **Step 1: Add the imports + the always-on test.** Replace the current import block (`:13-16`):
```swift
import CapsuleBackend
import XCTest

@testable import CapsuleCLIBackend
```
with the alphabetically ordered block (keeps `make lint`'s `OrderedImports` green):
```swift
import CapsuleApp
import CapsuleBackend
import CapsuleDomain
import XCTest

@testable import CapsuleCLIBackend
```
Then append, after `testRelocatedCLICommandYieldsRealCLIValidArgv` (before the class's closing brace), an **always-on** test (no `requireIntegration()`) that mirrors the M10 "guard skips cleanly without env" pattern — it scans the two real libexec dirs and treats an empty result as success, never failure:
```swift
    // MARK: - M11: plugin discovery (always-on; pure filesystem scan, no CLI, no mutation)

    /// Mirrors `testGuardSkipsCleanlyWithoutEnv`: runs unconditionally and asserts the scanner
    /// returns cleanly against the real libexec dirs whether or not any plugin is installed.
    func testLibexecPluginScannerRunsCleanlyAgainstRealDirs() throws {
        let scanner = LibexecPluginScanner()
        let plugins = scanner.installedPlugins()  // empty is success, not failure
        for plugin in plugins {
            XCTAssertFalse(plugin.name.isEmpty, "a discovered plugin must have a non-empty name")
            XCTAssertFalse(
                plugin.name.hasPrefix("container-"),
                "the container- prefix must be stripped (\(plugin.name))"
            )
            XCTAssertTrue(
                FileManager.default.isExecutableFile(atPath: plugin.path),
                "a discovered plugin must point at an executable (\(plugin.path))"
            )
        }
        let names = plugins.map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "plugin names must be de-duplicated")
    }
```

- [ ] **Step 2: Run it — expect FAIL (compile).** Run `make test`. Expected: a compile error in the integration target — `no such module 'CapsuleApp'` — because `LibexecPluginScanner` lives in `CapsuleApp`, which the test target does not yet depend on.

- [ ] **Step 3: Add the package dependency.** In `Package.swift`, change the `CapsuleIntegrationTests` target (`:114-117`) from:
```swift
        .testTarget(
            name: "CapsuleIntegrationTests",
            dependencies: ["CapsuleCLIBackend", "CapsuleBackend", "CapsuleDomain"]
        ),
```
to:
```swift
        .testTarget(
            name: "CapsuleIntegrationTests",
            dependencies: ["CapsuleApp", "CapsuleCLIBackend", "CapsuleBackend", "CapsuleDomain"]
        ),
```

- [ ] **Step 4: Run it — expect PASS.** Run `make test`. Expect `testLibexecPluginScannerRunsCleanlyAgainstRealDirs` to run unconditionally and pass (empty or populated), the gated argv probe from P6.1 to skip, and the full suite green.

- [ ] **Step 5: Commit.**
```
test(integration): libexec plugin scanner runs cleanly against real dirs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

### Task P6.3: Verify the relocation architecture guards (verification-only)

Phase 1 Task P1.1 already added the relocation guards to `ArchitectureGuardTests.swift`
(`testBackendDoesNotUseProcess`, `testRelocatedCommandFactoryLivesInBackend`,
`testCLIBackendStillOwnsTheProcessRunner`) and extended `testGuardActuallyFoundSources` to scan
`CapsuleBackend`. This task therefore **adds no methods and re-edits nothing** — re-adding them
would redeclare P1.1's methods (a compile error) and the `testGuardActuallyFoundSources`
old-string would no longer match after P1.1's rewrite. The remaining invariants this phase cares
about are also already guarded by the pre-existing suite: `testUIDoesNotImportAnyBackendModule`
(UI imports no Backend module) and `testDomainDoesNotUseProcess` (Domain stays Process-free). No
genuinely-new assertion is needed.

**Files:**
- None. Verification only — no source or test edits.

**Interfaces:**
- Consumes: the relocation guards added by P1.1; the pre-existing `testUIDoesNotImportAnyBackendModule`, `testDomainDoesNotUseProcess`, `testDomainDoesNotImportUI` in `ArchitectureGuardTests`.
- Produces: a verified-green architecture guard over the whole M11 branch (no code change).

- [ ] **Step 1: Confirm the P1.1 relocation guards are present and green.** Run `make test`. Expected: `ArchitectureGuardTests` is green and includes `testBackendDoesNotUseProcess`, `testRelocatedCommandFactoryLivesInBackend`, `testCLIBackendStillOwnsTheProcessRunner`, and the extended `testGuardActuallyFoundSources` (all added by P1.1), plus the pre-existing `testUIDoesNotImportAnyBackendModule` and `testDomainDoesNotUseProcess`. Do NOT re-add any of these — they already exist.

- [ ] **Step 2: Confirm the full CI gate is green.** Run `make ci`. Expected: build + lint + arch + headers + test all green across the M11 branch.

- [ ] **Step 3: Commit only if there are staged changes; otherwise note this is a verification-only task (no code change).** This task normally leaves the tree clean. If `git status --porcelain` is empty, record that P6.3 is verification-only and move on. If some earlier step left an incidental staged change, commit it:
```
test(arch): verify relocation guards are green over the M11 branch

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

### Task P6.4: `make ci` green + whole-branch 3-lens adversarial review

**Files:**
- Modify: only the files a confirmed review finding names (no speculative edits). If the review surfaces nothing, this task adds no source changes.

**Interfaces:**
- Consumes: nothing new — this is a whole-branch verification task over the M11 diff.
- Produces: a green `make ci` and a triaged review with Critical/High fixed.

- [ ] **Step 1: Run the full CI gate.** Run `make ci` (build + lint + arch + headers + test). Fix anything red. Confirm `ArchitectureGuardTests` is green and that **no UI file contains a forbidden `import CapsuleBackend` / `import CapsuleCLIBackend` / `import CapsuleTerminal` substring even inside a comment** (the naive `source.contains(...)` scan gotcha). Confirm with the flag unset (`make test`) that both `testGuardSkipsCleanlyWithoutEnv` and `testLibexecPluginScannerRunsCleanlyAgainstRealDirs` pass and the gated argv probe skips.

- [ ] **Step 2: Whole-branch 3-lens adversarial review.** Use `superpowers:requesting-code-review` over the entire M11 branch diff — the cross-cutting class of bugs per-task review misses — through three lenses:
  - **Correctness:** `CommandRedactor` never leaks a secret into `displayString` while `argv`/`arguments` stay raw (`-p`/`--publish` preserved; `--password`/`--passphrase`/`--token`/`--secret` value masked incl. `=value` form; `-e`/`--env`/`--build-arg` masked only when the KEY matches `(?i)(pass|secret|token|key|cred)`); `FuzzyMatch` ranking is a real subsequence match; `RunDraft`/`BuildDraft` `Codable` round-trips (esp. `BuildDraft.contextDirectory` path); preset decode failure falls back to an empty list.
  - **Layering:** no UI→Backend edge; Domain stays Process-free and UI-free; `CommandCatalog`/`CommandPaletteView`/`ShellState` stay in `CapsuleUI`; the relocated factory stays in `CapsuleBackend`; `LibexecPluginScanner` stays in `CapsuleApp`.
  - **State-not-rendered / leaks:** a model field nobody renders (e.g. `OperationTask.invocation` not shown in `TaskTranscriptView`); a palette action whose `isEnabled` never recomputes when selection changes; plugin entries not re-gated when `health.isRunning` flips; a leaked follow stream from the Command Console/terminal escalation.
  Triage findings by severity; fix Critical/High and re-run `make ci` to re-verify.

- [ ] **Step 3: Commit any fixes** (skip if the review found nothing actionable).
```
fix(m11): address whole-branch review findings

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```

### Task P6.5: Live interactive GUI smoke of the headline flows

**Files:**
- Modify: only the files a smoke-found defect requires (none if the smoke is clean).

**Interfaces:**
- Consumes: the running `.app` (`make app`).
- Produces: a verified live smoke of the power-user flows; the branch ready for `superpowers:finishing-a-development-branch`.

- [ ] **Step 1: Build the app.** Run `make app` (XcodeGen + `xcodebuild` of the `Capsule` scheme). Launch it (`make run` or open the built `.app`).

- [ ] **Step 2: Run the live interactive GUI smoke checklist.** Exercise each headline flow and fix any issue found, then re-verify:
  1. **⌘K → run an action.** Press ⌘K → the Command Palette opens; fuzzy-type a query; Return runs the first enabled match. Verify "Open System Logs" lands on **System ▸ Service Logs** and "Reclaim Disk Space" on **System ▸ Storage** (via `shell.systemTab`), proving the deep-link.
  2. **Selection gating.** With no image selected, "Run Selected Image…" renders disabled with a hint subtitle; select an image → it enables and `shell.present(.run(imageReference:))` opens `QuickRunSheet`. Confirm the menu bar mirrors the same enablement (one catalog, no drift).
  3. **Copy a sheet preview (secrets honest).** Open a sheet (QuickRun/Build); `CommandPreviewView` shows the exact argv; Copy puts `displayString` on the clipboard. Add `-e SECRET=hunter2` and confirm the value is masked in the preview/copy but the real run uses the raw value; confirm a `-p 8080:80` publish mapping is **not** masked.
  4. **Save + re-run a Run preset.** Configure a Run sheet → "Save as preset…" → name it. The preset appears in the **Presets** menu and the palette; selecting it re-opens `QuickRunSheet` pre-filled and ready; delete it and confirm it disappears from both surfaces.
  5. **Escalate via the Command Console.** Open "Open Raw Command Preview"; the Console seeds from the current selection/sheet; edit the argv; "Run in Terminal" (embedded) and "Run in Terminal.app" (external) both launch `container …`; an arbitrary passthrough (e.g. `container --version`) runs.
  6. **Plugin route (or passthrough fallback).** With the system service running, a plugin entry (`container-<name>`) appears in the palette/menu and routes to the terminal; stop the service and confirm it disappears (gated on `health.isRunning`). If no plugin is installed, confirm the Console passthrough runs an arbitrary `container` command instead.
  7. **Post-run "just ran".** After a task completes, the Activity pane / `TaskTranscriptView` renders the exact `task.invocation` argv, copyable.

- [ ] **Step 3: Commit fixes; branch ready.** Commit any smoke-found fixes, then hand off to `superpowers:finishing-a-development-branch`.
```
fix(m11): address GUI smoke findings

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K15VC9s6p3GJmidZKmDsnw
```
