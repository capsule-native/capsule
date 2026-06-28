# Milestone 5C · Destructive lifecycle (kill / delete / prune / export) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or subagent-driven-development). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add the destructive container lifecycle — `kill`/Force-Stop, `delete`/`rm` (single + bulk), `prune` (Cleanup sheet), and `export` (save panel) — with confirmation sheets, dependency guidance, and the normalized error/retry-in-terminal path, on top of 5B's `ContainerLifecycleModel`.

**Architecture:** Ports & Adapters; new Backend value type `PruneResult` (Foundation-only); a pure `ConfirmationRequest` domain value type drives a single generic `ConfirmationSheet`. Embedded terminal stays M6.

**Tech Stack:** Swift 6, SwiftUI (macOS 26+), `Observation`, XCTest, `NSSavePanel`/`NSPasteboard` (AppKit, UI layer only).

## Global Constraints

- Arch guard: `CapsuleUI` imports no Backend module / names no Backend type; `CapsuleDomain` imports no UI and no `Foundation.Process`. Domain may import `CapsuleBackend`.
- License header per file; `swift-format --strict`; zero-warning build; `make ci` green.
- Tests under Xcode toolchain: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter <Suite>`.
- TDD: failing test → fail → minimal impl → pass → commit. Commit trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- CLI: `kill [-s <sig>] <ids>`; `delete [-f] <ids>`; `prune` (no flags, human "Reclaimed …" output, exit 0); `export -o <path> <id>`. No per-container size anywhere. Destructive ops exit 1 on failure.
- Decisions: confirm when >1 for kill; always confirm running/bulk delete; prune freed-space estimate is infeasible (show count/names + actual reclaimed string); export validates stopped-state; 5B hang Force Stop re-routes to real `kill`.

---

### Task 1: Backend — `PruneResult` + port methods (kill/prune/export)

**Files:** Modify `Sources/CapsuleBackend/BackendLifecycleTypes.swift`, `ContainerBackend.swift`, `MockBackend.swift`. Test `Tests/CapsuleUnitTests/MockBackendTests.swift`.

**Interfaces — Produces:** `struct PruneResult { var reclaimedDescription: String?; var raw: String }`; `killContainer(id:signal:)`, `pruneContainers() -> PruneResult`, `exportContainer(id:to: URL)` on `ContainerBackend`; `MockBackend` impls + `lastKillSignal`, `lastExportURL`.

- [ ] **Step 1: Failing tests** (MockBackendTests):

```swift
func testKillRecordsSignalAndStops() async throws {
    let backend = MockBackend()
    try await backend.killContainer(id: "a1b2c3d4", signal: "TERM")
    XCTAssertEqual(backend.lastKillSignal, "TERM")
    let c = try await backend.listContainers(all: true).first { $0.id == "a1b2c3d4" }
    XCTAssertEqual(c?.state, "stopped")
}

func testPruneRemovesStoppedAndReportsReclaimed() async throws {
    let backend = MockBackend()
    let result = try await backend.pruneContainers()
    let all = try await backend.listContainers(all: true)
    XCTAssertFalse(all.contains { $0.state == "stopped" })
    XCTAssertNotNil(result.reclaimedDescription)
}

func testExportRecordsURL() async throws {
    let backend = MockBackend()
    let url = URL(fileURLWithPath: "/tmp/x.tar")
    try await backend.exportContainer(id: "a1b2c3d4", to: url)
    XCTAssertEqual(backend.lastExportURL, url)
}
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3:** Add `PruneResult` to `BackendLifecycleTypes.swift`:

```swift
/// The result of `container prune`. The CLI prints a human "Reclaimed … in disk space" line
/// (no JSON, no per-item breakdown), so `reclaimedDescription` is best-effort and `raw` keeps
/// the full stdout+stderr for display/diagnostics.
public struct PruneResult: Sendable, Equatable {
    public var reclaimedDescription: String?
    public var raw: String

    public init(reclaimedDescription: String? = nil, raw: String = "") {
        self.reclaimedDescription = reclaimedDescription
        self.raw = raw
    }
}
```

- [ ] **Step 4:** Add to `ContainerBackend` protocol (in the Containers MARK):

```swift
    func killContainer(id: String, signal: String?) async throws
    func pruneContainers() async throws -> PruneResult
    func exportContainer(id: String, to url: URL) async throws
```

- [ ] **Step 5:** Implement in `MockBackend` (add `lastKillSignal`, `lastExportURL` stored props):

```swift
    public private(set) var lastKillSignal: String?
    public private(set) var lastExportURL: URL?
```
```swift
    public func killContainer(id: String, signal: String?) async throws {
        try withState { state in
            state.lastKillSignal = signal
            state.mutateContainer(id) {
                $0.state = "stopped"
                $0.ip = nil
            }
        }
    }

    public func pruneContainers() async throws -> PruneResult {
        try withState { state in
            let removed = state.containers.filter { $0.state != "running" }.count
            state.containers.removeAll { $0.state != "running" }
            return PruneResult(
                reclaimedDescription: "Reclaimed \(removed) item(s).", raw: "")
        }
    }

    public func exportContainer(id: String, to url: URL) async throws {
        try withState { state in state.lastExportURL = url }
    }
```

- [ ] **Step 6: Run → pass. Commit** — `feat(backend): PruneResult + kill/prune/export on the port`.

---

### Task 2: CLI — kill/prune/export argv + prune parser

**Files:** Modify `Sources/CapsuleCLIBackend/CLICommand.swift`, `OutputParser.swift`, `CLIContainerBackend.swift`. Test `CLICommandTests.swift`, `OutputParserTests.swift`, `CLIContainerBackendTests.swift`.

**Interfaces — Produces:** `CLICommand.killContainer(id:signal:)`, `pruneContainers()`, `exportContainer(id:to:)`; `OutputParser.parsePruneResult(stdout:stderr:) -> PruneResult`; adapter impls.

- [ ] **Step 1: Failing tests** (CLICommandTests):

```swift
func testDestructiveCommands() {
    XCTAssertEqual(CLICommand.killContainer(id: "a", signal: nil), ["kill", "a"])
    XCTAssertEqual(CLICommand.killContainer(id: "a", signal: "TERM"), ["kill", "--signal", "TERM", "a"])
    XCTAssertEqual(CLICommand.pruneContainers(), ["prune"])
    XCTAssertEqual(
        CLICommand.exportContainer(id: "a", to: URL(fileURLWithPath: "/tmp/x.tar")),
        ["export", "--output", "/tmp/x.tar", "a"])
}
```

OutputParserTests:

```swift
func testParsePruneResultFindsReclaimedOnEitherStream() {
    let a = OutputParser.parsePruneResult(stdout: "Reclaimed 75 MB in disk space\n", stderr: "")
    XCTAssertEqual(a.reclaimedDescription, "Reclaimed 75 MB in disk space")
    let b = OutputParser.parsePruneResult(stdout: "", stderr: "Reclaimed Zero KB in disk space")
    XCTAssertEqual(b.reclaimedDescription, "Reclaimed Zero KB in disk space")
    let c = OutputParser.parsePruneResult(stdout: "noise", stderr: "")
    XCTAssertNil(c.reclaimedDescription)
    XCTAssertTrue(c.raw.contains("noise"))
}
```

CLIContainerBackendTests:

```swift
func testKillAndExportArgv() async throws {
    let stub = StubProcessRunner()
    let backend = makeBackend(stub)
    try await backend.killContainer(id: "c1", signal: nil)
    XCTAssertEqual(stub.lastCall, ["kill", "c1"])
    try await backend.exportContainer(id: "c1", to: URL(fileURLWithPath: "/tmp/c1.tar"))
    XCTAssertEqual(stub.lastCall, ["export", "--output", "/tmp/c1.tar", "c1"])
}
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3:** `CLICommand` (in Containers MARK):

```swift
    public static func killContainer(id: String, signal: String?) -> [String] {
        ArgumentBuilder("kill").flag("--signal", signal).adding(id).arguments
    }

    public static func pruneContainers() -> [String] {
        ArgumentBuilder("prune").arguments
    }

    public static func exportContainer(id: String, to url: URL) -> [String] {
        ArgumentBuilder("export").flag("--output", url.path).adding(id).arguments
    }
```

- [ ] **Step 4:** `OutputParser`:

```swift
    /// Extracts the "Reclaimed … in disk space" line from prune output (stdout or stderr;
    /// the CLI's stream choice is unverified), keeping the full combined text in `raw`.
    public static func parsePruneResult(stdout: String, stderr: String) -> PruneResult {
        let combined = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        let line = combined.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.range(of: "Reclaimed", options: .caseInsensitive) != nil
                && $0.range(of: "disk space", options: .caseInsensitive) != nil }
        return PruneResult(reclaimedDescription: line, raw: combined)
    }
```

- [ ] **Step 5:** `CLIContainerBackend`:

```swift
    public func killContainer(id: String, signal: String?) async throws {
        _ = try await runChecked(CLICommand.killContainer(id: id, signal: signal))
    }

    public func pruneContainers() async throws -> PruneResult {
        // prune exits 0 on success and prints a human line; do not treat stderr as failure.
        let result = try await runner.run(CLICommand.pruneContainers(), environment: [:])
        guard result.isSuccess else {
            throw BackendError.nonZeroExit(
                command: "container prune", code: result.exitCode, stderr: result.stderr)
        }
        return OutputParser.parsePruneResult(stdout: result.stdout, stderr: result.stderr)
    }

    public func exportContainer(id: String, to url: URL) async throws {
        _ = try await runChecked(CLICommand.exportContainer(id: id, to: url))
    }
```

(`runner` is the existing `ProcessRunning` seam; `runChecked` already exists.)

- [ ] **Step 6: Run → pass. Commit** — `feat(cli): kill/prune/export argv + adapter + prune parser`.

---

### Task 3: Domain — `ConfirmationRequest`

**Files:** Create `Sources/CapsuleDomain/Confirmation.swift`. Test `Tests/CapsuleUnitTests/ConfirmationTests.swift`.

**Interfaces — Produces:** `ConfirmationRequest` (+ `ConfirmationKind`) value type and static builders that encode *when* a sheet is required.

- [ ] **Step 1: Failing tests:**

```swift
//
//  ConfirmationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class ConfirmationTests: XCTestCase {
    func testKillRequiresConfirmationOnlyForMultiple() {
        XCTAssertNil(ConfirmationRequest.kill(ids: ["a"]))           // single: no sheet
        XCTAssertNotNil(ConfirmationRequest.kill(ids: ["a", "b"]))   // bulk: sheet
    }

    func testDeleteAlwaysConfirmsAndCarriesForce() {
        let single = ConfirmationRequest.delete(ids: ["a"], anyRunning: false)
        XCTAssertNotNil(single)
        XCTAssertEqual(single?.kind, .delete(force: false))
        let running = ConfirmationRequest.delete(ids: ["a"], anyRunning: true)
        XCTAssertEqual(running?.kind, .delete(force: true))
        XCTAssertTrue(running?.message.localizedCaseInsensitiveContains("stop") ?? false)
    }

    func testExportNotStoppedConfirmation() {
        let r = ConfirmationRequest.exportNotStopped(id: "a")
        XCTAssertEqual(r.kind, .exportNotStopped)
        XCTAssertEqual(r.targetIDs, ["a"])
    }
}
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement** `Confirmation.swift`:

```swift
//
//  Confirmation.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. A confirmation is
//  pure data so the UI renders it with one generic sheet and the policy is unit-testable.

import Foundation

public enum ConfirmationKind: Sendable, Equatable {
    case kill
    case delete(force: Bool)
    case exportNotStopped
}

public struct ConfirmationRequest: Sendable, Equatable, Identifiable {
    public var id: String { "\(kind)-\(targetIDs.joined(separator: ","))" }
    public var title: String
    public var message: String
    public var confirmTitle: String
    public var targetIDs: [String]
    public var kind: ConfirmationKind

    public init(
        title: String, message: String, confirmTitle: String,
        targetIDs: [String], kind: ConfirmationKind
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.targetIDs = targetIDs
        self.kind = kind
    }

    /// A confirmation is needed for Force Stop (kill) only when more than one is targeted.
    public static func kill(ids: [String]) -> ConfirmationRequest? {
        guard ids.count > 1 else { return nil }
        return ConfirmationRequest(
            title: "Force Stop \(ids.count) containers?",
            message: "This sends SIGKILL immediately. Unsaved work in these containers is lost.",
            confirmTitle: "Force Stop", targetIDs: ids, kind: .kill)
    }

    /// Delete always confirms; a running target requires force and a Stop-first recommendation.
    public static func delete(ids: [String], anyRunning: Bool) -> ConfirmationRequest? {
        let count = ids.count
        let noun = count == 1 ? "container" : "\(count) containers"
        let base = "Deleting \(noun) is permanent."
        let message =
            anyRunning
            ? base + " A running container must be stopped first; deleting it now forces removal."
            : base
        return ConfirmationRequest(
            title: "Delete \(noun)?", message: message,
            confirmTitle: anyRunning ? "Force Delete" : "Delete",
            targetIDs: ids, kind: .delete(force: anyRunning))
    }

    public static func exportNotStopped(id: String) -> ConfirmationRequest {
        ConfirmationRequest(
            title: "Export a running container?",
            message: "Exporting a running container may capture an inconsistent filesystem. "
                + "Stopping it first is recommended.",
            confirmTitle: "Export Anyway", targetIDs: [id], kind: .exportNotStopped)
    }
}
```

- [ ] **Step 4: Run → pass. Commit** — `feat(domain): ConfirmationRequest policy value type`.

---

### Task 4: Domain — destructive actions on `ContainerLifecycleModel`

**Files:** Modify `Sources/CapsuleDomain/ContainerLifecycleModel.swift`. Test `ContainerLifecycleModelTests.swift`.

**Interfaces — Produces:** `kill(id:signal:)`, `killAll(ids:)`, `delete(id:force:)`, `deleteAll(ids:force:)`, `prune() -> PruneResult`, `computePruneTargets() -> [Container]`, `export(id:to:URL)`, `validateExport(id:) -> Bool`; published `confirmation: ConfirmationRequest?`; hang Force Stop re-routed to `kill`.

- [ ] **Step 1: Failing tests** (add to `ContainerLifecycleModelTests`):

```swift
func testKillRecordsSignalAndReportsStopped() async {
    let backend = MockBackend()
    let m = model(backend: backend, state: { _ in .stopped })
    let outcome = await m.kill(id: "a1b2c3d4", signal: nil)
    XCTAssertEqual(outcome, .stopped)
}

func testDeleteUsesForceFlag() async {
    let backend = MockBackend()
    let m = model(backend: backend)
    await m.delete(id: "a1b2c3d4", force: true)
    let remaining = (try? await backend.listContainers(all: true))?.map(\.id) ?? []
    XCTAssertFalse(remaining.contains("a1b2c3d4"))
}

func testComputePruneTargetsAreStoppedOnly() async {
    let m = model(backend: MockBackend())
    let targets = await m.computePruneTargets()
    XCTAssertTrue(targets.allSatisfy { $0.state != .running })
    XCTAssertTrue(targets.contains { $0.id == "e5f6a7b8" })  // the seeded stopped one
}

func testPruneReportsReclaimed() async {
    let m = model(backend: MockBackend())
    let result = await m.prune()
    XCTAssertNotNil(result.reclaimedDescription)
}

func testValidateExportFailsForRunning() {
    let m = model(state: { id in id == "run" ? .running : .stopped })
    XCTAssertFalse(m.validateExport(id: "run"))
    XCTAssertTrue(m.validateExport(id: "other"))
}
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement.** Add a published `public var confirmation: ConfirmationRequest?` and a `// MARK: - Destructive` section:

```swift
    public func kill(id: String, signal: String? = nil) async -> StopOutcome {
        busy.insert(id)
        defer { busy.remove(id) }
        do {
            try await backend.killContainer(id: id, signal: signal)
            await reloadList()
            onActivity("Force-stopped “\(id)”.")
            return .stopped
        } catch {
            if isBenignAlreadyStopped(error) {
                onActivity("“\(id)” was already stopped.")
                return .alreadyStopped
            }
            let detail = normalize(error).detail
            notice = LifecycleNotice(detail: detail)
            return .failed(detail)
        }
    }

    public func killAll(ids: [String]) async {
        for id in ids { _ = await kill(id: id) }
    }

    public func delete(id: String, force: Bool) async {
        busy.insert(id)
        defer { busy.remove(id) }
        do {
            try await backend.removeContainer(id: id, force: force)
            await reloadList()
            onActivity("Deleted “\(id)”.")
        } catch {
            if isBenignAlreadyStopped(error) {
                // A not-found on delete is effectively "already gone".
                await reloadList()
                onActivity("“\(id)” was already removed.")
                return
            }
            notice = LifecycleNotice(detail: normalize(error).detail)
        }
    }

    public func deleteAll(ids: [String], force: Bool) async {
        for id in ids { await delete(id: id, force: force) }
    }

    public func computePruneTargets() async -> [Container] {
        let all = (try? await backend.listContainers(all: true)) ?? []
        return all.map(Container.init(summary:)).filter { $0.state != .running }
    }

    public func prune() async -> PruneResult {
        do {
            let result = try await backend.pruneContainers()
            await reloadList()
            onActivity(result.reclaimedDescription ?? "Cleanup complete.")
            return result
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
            return PruneResult()
        }
    }

    /// Returns false when the container is running (export should warn first).
    public func validateExport(id: String) -> Bool {
        currentState(id) != .running
    }

    public func export(id: String, to url: URL) async {
        busy.insert(id)
        defer { busy.remove(id) }
        do {
            try await backend.exportContainer(id: id, to: url)
            onActivity("Exported “\(id)” to \(url.lastPathComponent).")
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
        }
    }
```

Re-route the hang Force Stop to the real kill: in `makeHangNotice` keep `forceStopID`, and in `AppShellView` the Force Stop button (Task 6) calls `kill(id:)` instead of `forceStop(id:)`. (Leave `forceStop`/`stop -t 0` as a still-valid graceful-force, but the destructive escalation now uses kill.)

`PruneResult` is a Backend type returned by `prune()`/the backend — the model returns it to the UI. **Arch check:** `PruneResult` would then appear in a UI call site. To avoid a Backend type in UI, have `prune()` return a **domain** value: add `public struct PruneSummary: Sendable, Equatable { public var message: String }` in `Lifecycle.swift`, map `PruneResult.reclaimedDescription ?? "Cleanup complete."` into it, and return `PruneSummary` from the model. Update the test to assert `result.message`.

- [ ] **Step 4: Run → pass** (update the prune test to use `PruneSummary.message`). **Commit** — `feat(domain): destructive lifecycle actions (kill/delete/prune/export) + confirmation state`.

---

### Task 5: UI — ConfirmationSheet + PruneSheet

**Files:** Create `Sources/CapsuleUI/ConfirmationSheet.swift`, `PruneSheet.swift`.

**Interfaces:** SwiftUI views binding to `ConfirmationRequest` / the lifecycle model. Verified by build + inspection.

- [ ] **Step 1: Implement `ConfirmationSheet`** — renders a `ConfirmationRequest`: title, message, a destructive `confirmTitle` button (`role: .destructive`, `.borderedProminent`), Cancel; calls `onConfirm`/`onCancel`. `make build`.
- [ ] **Step 2: Implement `PruneSheet`** — on `.task`, `let targets = await lifecycle.computePruneTargets()`; show count + names (scrollable) + the honest "Freed space can't be estimated in advance." note; empty-state when none; a "Clean Up" destructive button → `await lifecycle.prune()` then show `summary.message` and dismiss; Cancel. `make build`.
- [ ] **Step 3: Commit** — `feat(ui): ConfirmationSheet + PruneSheet (Cleanup)`.

---

### Task 6: UI wiring — destructive menu, export save panel, hang→kill

**Files:** Modify `Sources/CapsuleUI/ContainerListView.swift`, `AppShellView.swift`, `LifecycleSheet` enum.

- [ ] **Step 1:** Extend `LifecycleSheet` with `.confirm(ConfirmationRequest)` and `.prune`; add an `.export(id:name:)` flow (NSSavePanel, not a sheet).
- [ ] **Step 2:** In `ContainerListView`, add a destructive context-menu section + toolbar items: **Force Stop** (kill — builds `ConfirmationRequest.kill(ids:)`; if nil, kills directly; else present `.confirm`), **Delete** (⌫ key + menu; `ConfirmationRequest.delete(ids:anyRunning:)` → present `.confirm`), **Clean Up…** (present `.prune`), **Export…** (single; if `!lifecycle.validateExport(id:)` present `.confirm(.exportNotStopped)` first, else open the save panel). All destructive items `role: .destructive`.
- [ ] **Step 3:** Save panel helper (AppKit): `NSSavePanel` defaulting `nameFieldStringValue = "\(name).tar"`; on `.OK`, `Task { await lifecycle.export(id: id, to: url) }`.
- [ ] **Step 4:** Confirm-sheet handler maps `kind` → action: `.kill` → `killAll(ids:)`; `.delete(force)` → `deleteAll(ids:force:)`; `.exportNotStopped` → open save panel.
- [ ] **Step 5:** In `AppShellView`, change the hang-notice Force Stop button to call `lifecycleModel.kill(id:)` (real destructive escalation) instead of `forceStop`.
- [ ] **Step 6:** `make build` (zero warnings). **Commit** — `feat(ui): destructive lifecycle menu, export save panel, hang→kill`.

---

### Task 7: Verify + adversarial review

- [ ] **Step 1:** `make ci` green (build, swift-format, arch guard, headers, all tests). `make format` if needed.
- [ ] **Step 2:** `make app` + launch smoke (destructive menu items appear; Clean Up sheet opens; daemon-down still health-gated). Visual pass by inspection (0 containers locally).
- [ ] **Step 3 (ultracode):** adversarial review workflow over the 5C diff (arch-guard, confirmation-policy correctness, prune-parser fidelity, error/benign handling, test coverage); apply confirmed fixes.
- [ ] **Step 4:** Commit any fixes.

---

## Self-Review

**Spec coverage:** kill+confirm-when-multiple → Tasks 1–4 (`kill`/`killAll`, `ConfirmationRequest.kill`), 6; delete single+bulk+force+guidance → Tasks 1,4 (`delete`/`deleteAll`), 3 (`ConfirmationRequest.delete`), 6; prune Cleanup sheet + precompute + honest estimate + actual reclaimed → Tasks 1–2 (`PruneResult`/parser), 4 (`computePruneTargets`/`prune`→`PruneSummary`), 5 (`PruneSheet`); export save panel + stopped-state validation → Tasks 1–2 (`exportContainer`), 4 (`validateExport`/`export`), 6 (NSSavePanel + caution); confirmation sheets for bulk/destructive → Tasks 3,5,6; hang→real kill → Tasks 4,6; normalized errors + retry-in-terminal → reuses 5B (`notice`/clipboard). ✔

**Arch guard:** `PruneResult` (Backend) is mapped to domain `PruneSummary` before the UI; no Backend type in a UI signature; `ConfirmationRequest`/`ConfirmationKind` are domain types; NSSavePanel/NSPasteboard are UI-layer AppKit. ✔

**Placeholder scan:** every code step has real code; the "explain dependencies" guidance is concrete in `ConfirmationRequest.delete`. ✔

**Type consistency:** `ConfirmationKind` cases (`kill`, `delete(force:)`, `exportNotStopped`) match across Tasks 3,6; model method names (`kill`/`killAll`/`delete`/`deleteAll`/`prune`/`computePruneTargets`/`export`/`validateExport`) stable Tasks 4–6; `PruneSummary.message` used in Tasks 4–5. ✔
