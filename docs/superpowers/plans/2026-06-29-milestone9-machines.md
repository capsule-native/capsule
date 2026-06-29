# Milestone 9 · Machines Surface — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a full Machines surface (list/create/run-shell/inspect/set/set-default/logs/stop/delete) over the `container machine` CLI, making delayed-effect config (restart-required) and implicit boots obvious — the place a GUI beats the CLI.

**Architecture:** Mirror the M8 Networks vertical slice across the strict layers (UI → Domain → Backend port → CLI adapter → MockBackend) and reuse existing terminal/logs/task/error infrastructure. The `.machines` capability flag, `SidebarSection.machines`, and `listMachines()` plumbing already exist; this fills in the `ContentColumnView` `.machines` case and everything behind it.

**Tech Stack:** Swift 6, SwiftUI, Observation (`@Observable`), Swift Testing/XCTest, XcodeGen app target.

## Global Constraints

- **Layering (arch guard `Tests/CapsuleUnitTests/ArchitectureGuardTests` + `Scripts/check-architecture.sh`):** `CapsuleUI` imports NO Backend module; `CapsuleDomain` imports NO UI and NO `Foundation.Process`. Domain models inject closures (`launchTerminal`, `copyCommand`, `onActivity`, `currentState`) instead of calling UI/Process.
- **Build/test toolchain:** XCTest/`swift test`/`xcodebuild` require Xcode — the `Makefile` exports `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Always go through `make`: `make build`, `make test`, `make ci`, `make app`, `make arch`.
- **Minimum CLI:** client ≥ `1.0.0`; `.machines` is a runtime feature requiring the system service up (server version present). Apple-silicon/macOS 26+ envelope is already enforced app-wide.
- **CLI ground truth (v1.0.0):** `machine create <image>` flags = `-n/--name`, `--set-default`, `--no-boot`, `--cpus`, `--memory`, `--home-mount <ro|rw|none>`, `-a/--arch`, `--os`, `--platform`. **No `--nested-virtualization`, no `--kernel`.** `machine set [-n <name>] cpus=<n> memory=<size> home-mount=<…>` (takes effect after restart). `machine set-default <id>`. `machine logs [--boot] [-f] [-n <lines>] [<id>]`. `machine run [-n <name>] [-i -t] …` (boots if needed). `machine stop [<id>]`. `machine delete <id>` (removes persistent storage). `machine inspect [<id>]` (JSON, no `--format`). `machine list --format json`.
- **Unicode:** the Write tool can mangle curly quotes (`“”`) into ASCII `"` (parse error). In Swift string literals, write them as `\u{201c}` / `\u{201d}` (project lint allows curly quotes in literals). Match the existing `“…”` activity-message style used in `ContainerLifecycleModel`/`NetworkActionsModel`.
- **License header:** every new file needs the standard header (the `pre-commit: license headers` hook enforces it). Copy the 6-line header block from any existing file in the same module.
- **Decision locks (from the spec):** nested-virt/kernel are omitted from create/set, shown read-only in the inspector only if present in inspect JSON. The command palette is NOT built (M11 owns it) — ship toolbar + Machine menu + context actions. One real machine is created+deleted during Phase H to lock wire-shape fixtures.
- **Editor lag gotcha:** SourceKit diagnostics lag after adding types (false "cannot find type"). Trust `make build`/`make test` exit codes, not the editor.
- **Commit message footer (every commit):**
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he
  ```

---

## Phase A — Backend port, value types, MockBackend, CLI adapter

### Task A1: Expand `MachineSummary` to the real `list` columns

**Files:**
- Modify: `Sources/CapsuleBackend/BackendResourceTypes.swift:134-144`
- Test: `Tests/CapsuleUnitTests/MachineSummaryTests.swift` (create)

**Interfaces:**
- Produces: `MachineSummary { id:String{name}, name:String, state:String?, createdAt:String?, ipAddress:String?, cpus:Int?, memory:String?, disk:String?, isDefault:Bool, kernel:String?, nestedVirtualization:Bool?, homeMount:String? }` — `Sendable, Equatable, Identifiable, Codable`, memberwise `init` with defaults for every field except `name`.

- [ ] **Step 1: Write the failing test**

```swift
//  MachineSummaryTests.swift  (+ license header)
import XCTest
@testable import CapsuleBackend

final class MachineSummaryTests: XCTestCase {
    func test_init_defaults_onlyNameRequired() {
        let m = MachineSummary(name: "dev")
        XCTAssertEqual(m.id, "dev")
        XCTAssertNil(m.state)
        XCTAssertFalse(m.isDefault)
        XCTAssertNil(m.cpus)
    }

    func test_carriesListColumns() {
        let m = MachineSummary(
            name: "dev", state: "running", createdAt: "2026-06-29T00:00:00Z",
            ipAddress: "192.168.66.2", cpus: 4, memory: "8G", disk: "20G", isDefault: true)
        XCTAssertEqual(m.cpus, 4)
        XCTAssertEqual(m.memory, "8G")
        XCTAssertTrue(m.isDefault)
        XCTAssertEqual(m.ipAddress, "192.168.66.2")
    }
}
```

- [ ] **Step 2: Run, expect FAIL** — `make test` (compile error: extra args). 
- [ ] **Step 3: Replace the `MachineSummary` struct** in `BackendResourceTypes.swift`:

```swift
/// A backend's lightweight view of a container machine (`machine list`).
public struct MachineSummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String { name }
    public var name: String
    public var state: String?
    /// Raw creation timestamp (ISO-8601 or CLI display string); the domain parses it.
    public var createdAt: String?
    public var ipAddress: String?
    public var cpus: Int?
    public var memory: String?
    public var disk: String?
    public var isDefault: Bool
    // Inspect-only detail (absent from `list`); surfaced read-only when present.
    public var kernel: String?
    public var nestedVirtualization: Bool?
    public var homeMount: String?

    public init(
        name: String, state: String? = nil, createdAt: String? = nil, ipAddress: String? = nil,
        cpus: Int? = nil, memory: String? = nil, disk: String? = nil, isDefault: Bool = false,
        kernel: String? = nil, nestedVirtualization: Bool? = nil, homeMount: String? = nil
    ) {
        self.name = name
        self.state = state
        self.createdAt = createdAt
        self.ipAddress = ipAddress
        self.cpus = cpus
        self.memory = memory
        self.disk = disk
        self.isDefault = isDefault
        self.kernel = kernel
        self.nestedVirtualization = nestedVirtualization
        self.homeMount = homeMount
    }
}
```

- [ ] **Step 4: Run, expect PASS** — `make test`.
- [ ] **Step 5: Commit** — `feat(backend): expand MachineSummary to real machine list columns`.

---

### Task A2: `MachineConfiguration` (create argv builder)

**Files:**
- Create: `Sources/CapsuleBackend/MachineConfiguration.swift`
- Test: `Tests/CapsuleUnitTests/MachineConfigurationTests.swift`

**Interfaces:**
- Produces: `MachineConfiguration { image:String, name:String?, cpus:Int?, memory:String?, homeMount:String?, arch:String?, os:String?, platform:String?, setDefault:Bool, noBoot:Bool }` (`Sendable, Equatable`) with `var arguments: [String]` → the `machine create …` argv (NOT prefixed with `container`). Image is the trailing positional.

- [ ] **Step 1: Failing test**

```swift
//  MachineConfigurationTests.swift  (+ header)
import XCTest
@testable import CapsuleBackend

final class MachineConfigurationTests: XCTestCase {
    func test_minimal_imageOnly() {
        let c = MachineConfiguration(image: "alpine:3.22")
        XCTAssertEqual(c.arguments, ["machine", "create", "alpine:3.22"])
    }

    func test_full_orderedFlagsThenImage() {
        let c = MachineConfiguration(
            image: "ubuntu:24.04", name: "dev", cpus: 4, memory: "8G", homeMount: "ro",
            arch: "arm64", os: "linux", platform: "linux/arm64", setDefault: true, noBoot: true)
        XCTAssertEqual(c.arguments, [
            "machine", "create",
            "--name", "dev", "--cpus", "4", "--memory", "8G", "--home-mount", "ro",
            "--arch", "arm64", "--os", "linux", "--platform", "linux/arm64",
            "--set-default", "--no-boot",
            "ubuntu:24.04",
        ])
    }
}
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** (uses the existing `ArgumentBuilder` fluent API — `flag(name,value?)` appends only when non-nil, `option(name,enabled:)` appends only when true):

```swift
//  MachineConfiguration.swift  (+ header)
import Foundation

/// Typed argv builder for `container machine create`. Single source of truth for create
/// arguments. `image` is the trailing positional; nested-virtualization and kernel are not
/// modelled because the CLI (v1.0.0) cannot set them.
public struct MachineConfiguration: Sendable, Equatable {
    public var image: String
    public var name: String?
    public var cpus: Int?
    public var memory: String?
    public var homeMount: String?
    public var arch: String?
    public var os: String?
    public var platform: String?
    public var setDefault: Bool
    public var noBoot: Bool

    public init(
        image: String, name: String? = nil, cpus: Int? = nil, memory: String? = nil,
        homeMount: String? = nil, arch: String? = nil, os: String? = nil, platform: String? = nil,
        setDefault: Bool = false, noBoot: Bool = false
    ) {
        self.image = image
        self.name = name
        self.cpus = cpus
        self.memory = memory
        self.homeMount = homeMount
        self.arch = arch
        self.os = os
        self.platform = platform
        self.setDefault = setDefault
        self.noBoot = noBoot
    }

    public var arguments: [String] {
        ArgumentBuilder("machine", "create")
            .flag("--name", name)
            .flag("--cpus", cpus.map(String.init))
            .flag("--memory", memory)
            .flag("--home-mount", homeMount)
            .flag("--arch", arch)
            .flag("--os", os)
            .flag("--platform", platform)
            .option("--set-default", enabled: setDefault)
            .option("--no-boot", enabled: noBoot)
            .adding(image)
            .arguments
    }
}
```

> NOTE: confirm `ArgumentBuilder` lives in `CapsuleCLIBackend`, not `CapsuleBackend`. The Networks analog `NetworkConfiguration` builds argv with a plain array literal inside `CapsuleBackend` (it does NOT import `ArgumentBuilder`). **Match that:** build the array manually so `CapsuleBackend` has no dependency on `CapsuleCLIBackend`:

```swift
    public var arguments: [String] {
        var argv = ["machine", "create"]
        if let name { argv += ["--name", name] }
        if let cpus { argv += ["--cpus", String(cpus)] }
        if let memory { argv += ["--memory", memory] }
        if let homeMount { argv += ["--home-mount", homeMount] }
        if let arch { argv += ["--arch", arch] }
        if let os { argv += ["--os", os] }
        if let platform { argv += ["--platform", platform] }
        if setDefault { argv.append("--set-default") }
        if noBoot { argv.append("--no-boot") }
        argv.append(image)
        return argv
    }
```

Use the manual-array form. Delete the ArgumentBuilder version.

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `feat(backend): MachineConfiguration create argv builder`.

---

### Task A3: `MachineSettings` (set argv builder)

**Files:**
- Modify: `Sources/CapsuleBackend/MachineConfiguration.swift` (append)
- Test: `Tests/CapsuleUnitTests/MachineConfigurationTests.swift` (append)

**Interfaces:**
- Produces: `MachineSettings { cpus:Int?, memory:String?, homeMount:String? }` (`Sendable, Equatable`) with `func arguments(name: String?) -> [String]` → `machine set [-n name] [cpus=…] [memory=…] [home-mount=…]`; `var isEmpty: Bool` (no fields set).

- [ ] **Step 1: Failing test (append)**

```swift
    func test_settings_nameAndTokens() {
        let s = MachineSettings(cpus: 4, memory: "8G", homeMount: "ro")
        XCTAssertEqual(s.arguments(name: "dev"),
            ["machine", "set", "--name", "dev", "cpus=4", "memory=8G", "home-mount=ro"])
    }
    func test_settings_omitName_partial() {
        let s = MachineSettings(memory: "2G")
        XCTAssertEqual(s.arguments(name: nil), ["machine", "set", "memory=2G"])
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(MachineSettings().isEmpty)
    }
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement (append to MachineConfiguration.swift)**

```swift
/// Typed argv builder for `container machine set` (cpus / memory / home-mount only — the
/// only settings the CLI accepts). Settings take effect after restart.
public struct MachineSettings: Sendable, Equatable {
    public var cpus: Int?
    public var memory: String?
    public var homeMount: String?

    public init(cpus: Int? = nil, memory: String? = nil, homeMount: String? = nil) {
        self.cpus = cpus
        self.memory = memory
        self.homeMount = homeMount
    }

    public var isEmpty: Bool { cpus == nil && memory == nil && homeMount == nil }

    public func arguments(name: String?) -> [String] {
        var argv = ["machine", "set"]
        if let name, !name.isEmpty { argv += ["--name", name] }
        if let cpus { argv.append("cpus=\(cpus)") }
        if let memory { argv.append("memory=\(memory)") }
        if let homeMount { argv.append("home-mount=\(homeMount)") }
        return argv
    }
}
```

- [ ] **Step 4: Run, expect PASS.** — [ ] **Step 5: Commit** — `feat(backend): MachineSettings set argv builder`.

---

### Task A4: Extend the `ContainerBackend` port with machine methods

**Files:**
- Modify: `Sources/CapsuleBackend/ContainerBackend.swift:164` (replace the lone `listMachines()` with the full machine block)

**Interfaces:**
- Produces (new protocol requirements):
  - `func inspectMachine(id: String?) async throws -> Parsed<MachineSummary>`
  - `func createMachine(_ config: MachineConfiguration) -> AsyncThrowingStream<OutputLine, Error>`
  - `func setMachine(name: String?, settings: MachineSettings) async throws`
  - `func setDefaultMachine(id: String) async throws`
  - `func stopMachine(id: String?) async throws`
  - `func deleteMachine(id: String) async throws`
  - `func fetchMachineLogs(id: String?, tail: Int?, boot: Bool) async throws -> [OutputLine]`
  - `func followMachineLogs(id: String?, boot: Bool) -> AsyncThrowingStream<OutputLine, Error>`

> Adding protocol requirements breaks compilation until BOTH `MockBackend` (A5) and `CLIContainerBackend` (A6) implement them. **This task does not build on its own** — do A4+A5+A6 as one commit (write the protocol, then both conformances, then build green). The steps below reflect that.

- [ ] **Step 1:** In `ContainerBackend.swift`, find `func listMachines() async throws -> [MachineSummary]` (line ~164) and add directly beneath it the eight signatures above, each with a one-line doc comment matching the volume/network doc style.
- [ ] **Step 2:** Build will fail (`MockBackend`/`CLIContainerBackend` no longer conform) — proceed to A5 and A6 before running.

---

### Task A5: `MockBackend` machine implementations + call-inspection + samples

**Files:**
- Modify: `Sources/CapsuleBackend/MockBackend.swift`
- Test: `Tests/CapsuleUnitTests/MockBackendMachineTests.swift` (create)

**Interfaces:**
- Consumes: A1 `MachineSummary`, A2 `MachineConfiguration`, A3 `MachineSettings`, A4 protocol methods.
- Produces: call-inspection props `lastCreatedMachine: MachineConfiguration?`, `lastMachineSettings: (name: String?, settings: MachineSettings)?`, `lastSetDefaultID: String?`, `lastStoppedMachine: String?`, `lastDeletedMachine: String?`; `static let sampleMachines: [MachineSummary]`.

- [ ] **Step 1: Failing test**

```swift
//  MockBackendMachineTests.swift  (+ header)
import XCTest
@testable import CapsuleBackend

final class MockBackendMachineTests: XCTestCase {
    func test_create_appendsAndRecords() async throws {
        let mock = MockBackend(machines: [])
        let cfg = MachineConfiguration(image: "alpine:3.22", name: "dev", setDefault: true)
        for try await _ in mock.createMachine(cfg) {}  // drain the stream
        XCTAssertEqual(mock.lastCreatedMachine, cfg)
        let list = try await mock.listMachines()
        XCTAssertEqual(list.map(\.name), ["dev"])
        XCTAssertTrue(list[0].isDefault)
    }

    func test_setDefault_flipsExclusive() async throws {
        let mock = MockBackend(machines: [
            MachineSummary(name: "a", isDefault: true), MachineSummary(name: "b")])
        try await mock.setDefaultMachine(id: "b")
        XCTAssertEqual(mock.lastSetDefaultID, "b")
        let list = try await mock.listMachines()
        XCTAssertEqual(Set(list.filter(\.isDefault).map(\.name)), ["b"])
    }

    func test_set_recordsAndApplies() async throws {
        let mock = MockBackend(machines: [MachineSummary(name: "dev", cpus: 2)])
        try await mock.setMachine(name: "dev", settings: MachineSettings(cpus: 8, memory: "16G"))
        XCTAssertEqual(mock.lastMachineSettings?.settings.cpus, 8)
        let dev = try await mock.listMachines().first { $0.name == "dev" }
        XCTAssertEqual(dev?.cpus, 8)
        XCTAssertEqual(dev?.memory, "16G")
    }

    func test_stop_thenDelete() async throws {
        let mock = MockBackend(machines: [MachineSummary(name: "dev", state: "running")])
        try await mock.stopMachine(id: "dev")
        XCTAssertEqual(mock.lastStoppedMachine, "dev")
        XCTAssertEqual(try await mock.listMachines().first?.state, "stopped")
        try await mock.deleteMachine(id: "dev")
        XCTAssertEqual(mock.lastDeletedMachine, "dev")
        XCTAssertTrue(try await mock.listMachines().isEmpty)
    }

    func test_inspect_defaultWhenNil() async throws {
        let mock = MockBackend(machines: [
            MachineSummary(name: "a"), MachineSummary(name: "b", isDefault: true)])
        let parsed = try await mock.inspectMachine(id: nil)
        XCTAssertEqual(parsed.value?.name, "b")  // default
        let byId = try await mock.inspectMachine(id: "a")
        XCTAssertEqual(byId.value?.name, "a")
    }

    func test_machineLogs_bootRespectsTail() async throws {
        let mock = MockBackend(machines: [MachineSummary(name: "dev")])
        let lines = try await mock.fetchMachineLogs(id: "dev", tail: 1, boot: true)
        XCTAssertEqual(lines.count, 1)
    }

    func test_sampleMachines_hasDefault() {
        XCTAssertTrue(MockBackend.sampleMachines.contains { $0.isDefault })
    }
}
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** — add call-inspection props near the network ones (after line ~85):

```swift
    /// The configuration of the most recent `createMachine` call.
    public private(set) var lastCreatedMachine: MachineConfiguration?
    /// The (name, settings) of the most recent `setMachine` call.
    public private(set) var lastMachineSettings: (name: String?, settings: MachineSettings)?
    /// The id of the most recent `setDefaultMachine` call.
    public private(set) var lastSetDefaultID: String?
    /// The id of the most recent `stopMachine` call.
    public private(set) var lastStoppedMachine: String?
    /// The id of the most recent `deleteMachine` call.
    public private(set) var lastDeletedMachine: String?
```

Replace the existing one-line `listMachines()` (line ~475) with the full machine block:

```swift
    public func listMachines() async throws -> [MachineSummary] { try withState { $0.machines } }

    public func inspectMachine(id: String?) async throws -> Parsed<MachineSummary> {
        try withState { state in
            let match = id.flatMap { wanted in state.machines.first { $0.name == wanted } }
                ?? state.machines.first { $0.isDefault } ?? state.machines.first
            return Parsed(value: match, raw: match.map { "\($0)" } ?? "")
        }
    }

    public func createMachine(_ config: MachineConfiguration)
        -> AsyncThrowingStream<OutputLine, Error>
    {
        lock.lock()
        lastCreatedMachine = config
        if !machines.contains(where: { $0.name == (config.name ?? config.image) }) {
            if config.setDefault { for i in machines.indices { machines[i].isDefault = false } }
            machines.append(MachineSummary(
                name: config.name ?? config.image,
                state: config.noBoot ? "stopped" : "running",
                cpus: config.cpus, memory: config.memory,
                isDefault: config.setDefault, homeMount: config.homeMount))
        }
        lock.unlock()
        return seededStream()
    }

    public func setMachine(name: String?, settings: MachineSettings) async throws {
        try withState { state in
            state.lastMachineSettings = (name, settings)
            let target = name ?? state.machines.first { $0.isDefault }?.name
            guard let target, let idx = state.machines.firstIndex(where: { $0.name == target })
            else { return }
            if let c = settings.cpus { state.machines[idx].cpus = c }
            if let m = settings.memory { state.machines[idx].memory = m }
            if let h = settings.homeMount { state.machines[idx].homeMount = h }
        }
    }

    public func setDefaultMachine(id: String) async throws {
        try withState { state in
            state.lastSetDefaultID = id
            for i in state.machines.indices { state.machines[i].isDefault = (state.machines[i].name == id) }
        }
    }

    public func stopMachine(id: String?) async throws {
        try withState { state in
            let target = id ?? state.machines.first { $0.isDefault }?.name
            state.lastStoppedMachine = target
            if let target, let idx = state.machines.firstIndex(where: { $0.name == target }) {
                state.machines[idx].state = "stopped"
            }
        }
    }

    public func deleteMachine(id: String) async throws {
        try withState { state in
            state.lastDeletedMachine = id
            state.machines.removeAll { $0.name == id }
        }
    }

    public func fetchMachineLogs(id: String?, tail: Int?, boot: Bool) async throws -> [OutputLine] {
        try withState { state in
            let lines = state.logLines
            if let tail, tail < lines.count { return Array(lines.suffix(tail)) }
            return lines
        }
    }

    public func followMachineLogs(id: String?, boot: Bool) -> AsyncThrowingStream<OutputLine, Error> {
        seededStream()
    }
```

Add the sample to the `extension MockBackend` block (near `sampleNetworks`):

```swift
    public static let sampleMachines: [MachineSummary] = [
        MachineSummary(
            name: "default", state: "running", createdAt: "2026-06-20T09:15:00Z",
            ipAddress: "192.168.66.2", cpus: 4, memory: "8G", disk: "20G", isDefault: true,
            homeMount: "rw"),
        MachineSummary(
            name: "builder", state: "stopped", createdAt: "2026-06-18T14:02:30Z",
            cpus: 2, memory: "4G", disk: "20G", isDefault: false, homeMount: "rw"),
    ]
```

> Keep the `machines:` init default `[]` (do NOT change to `sampleMachines` — existing tests assume empty). Tests/previews opt in explicitly.

- [ ] **Step 4: Build still fails** (CLI adapter) — proceed to A6; run `make test` after A6.
- [ ] **Step 5:** (commit at end of A6).

---

### Task A6: `CLIContainerBackend` machine implementations + commands + wire/parser

**Files:**
- Modify: `Sources/CapsuleCLIBackend/CLICommand.swift` (after `listMachines()` ~190)
- Modify: `Sources/CapsuleCLIBackend/CLIContainerBackend.swift` (after `listMachines()` ~358)
- Modify: `Sources/CapsuleCLIBackend/WireModels.swift` (expand `CLIMachineRecord` ~246)
- Modify: `Sources/CapsuleCLIBackend/OutputParser.swift` (expand `parseMachines` ~185; add `parseMachine` single)
- Test: `Tests/CapsuleUnitTests/CLICommandMachineTests.swift` (create), `Tests/CapsuleUnitTests/OutputParserMachineTests.swift` (create)

**Interfaces:**
- Consumes: A2/A3 argv builders, A4 protocol.
- Produces: `CLICommand.createMachine/setMachine/setDefaultMachine/stopMachine/deleteMachine/inspectMachine/machineLogs` static argv funcs; `OutputParser.parseMachines` (richer) + `parseMachine(_:) -> MachineSummary?`.

> The exact `list`/`inspect` JSON field names are NOT yet known (no machine exists locally). Use the **best-guess shape below** and keep decoding lossy; Phase H locks it against a real machine. The test fixtures here assert the parser is resilient (decodes what it can, drops what it can't) rather than asserting an exact upstream shape.

- [ ] **Step 1: Failing tests**

```swift
//  CLICommandMachineTests.swift  (+ header)
import XCTest
@testable import CapsuleCLIBackend
@testable import CapsuleBackend

final class CLICommandMachineTests: XCTestCase {
    func test_create_delegatesToConfig() {
        let cfg = MachineConfiguration(image: "alpine:3.22", name: "dev")
        XCTAssertEqual(CLICommand.createMachine(cfg), cfg.arguments)
    }
    func test_set_delegatesToSettings() {
        let s = MachineSettings(cpus: 4)
        XCTAssertEqual(CLICommand.setMachine(name: "dev", settings: s), s.arguments(name: "dev"))
    }
    func test_setDefault_stop_delete_inspect() {
        XCTAssertEqual(CLICommand.setDefaultMachine(id: "dev"), ["machine", "set-default", "dev"])
        XCTAssertEqual(CLICommand.stopMachine(id: "dev"), ["machine", "stop", "dev"])
        XCTAssertEqual(CLICommand.stopMachine(id: nil), ["machine", "stop"])
        XCTAssertEqual(CLICommand.deleteMachine(id: "dev"), ["machine", "delete", "dev"])
        XCTAssertEqual(CLICommand.inspectMachine(id: "dev"), ["machine", "inspect", "dev"])
        XCTAssertEqual(CLICommand.inspectMachine(id: nil), ["machine", "inspect"])
    }
    func test_logs_bootFollowTail() {
        XCTAssertEqual(CLICommand.machineLogs(id: "dev", tail: 100, boot: true, follow: false),
            ["machine", "logs", "--boot", "-n", "100", "dev"])
        XCTAssertEqual(CLICommand.machineLogs(id: nil, tail: nil, boot: false, follow: true),
            ["machine", "logs", "--follow"])
    }
}
```

```swift
//  OutputParserMachineTests.swift  (+ header)
import XCTest
@testable import CapsuleCLIBackend
@testable import CapsuleBackend

final class OutputParserMachineTests: XCTestCase {
    func test_parseMachines_listShape() throws {
        let json = """
        [{"name":"dev","state":"running","cpus":4,"memory":"8G","disk":"20G",
          "ipAddress":"192.168.66.2","default":true}]
        """
        let rows = try OutputParser.parseMachines(Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "dev")
        XCTAssertEqual(rows[0].cpus, 4)
        XCTAssertTrue(rows[0].isDefault)
    }
    func test_parseMachines_dropsUnnamed_keepsValid() throws {
        let json = #"[{"state":"running"},{"name":"ok"}]"#
        XCTAssertEqual(try OutputParser.parseMachines(Data(json.utf8)).map(\.name), ["ok"])
    }
    func test_parseMachine_single() throws {
        let json = #"{"name":"dev","state":"running"}"#
        XCTAssertEqual(OutputParser.parseMachine(Data(json.utf8))?.name, "dev")
    }
}
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3a:** `WireModels.swift` — replace `CLIMachineRecord` (~246):

```swift
struct CLIMachineRecord: Decodable {
    let name: String?
    let state: String?
    let cpus: Int?
    let memory: String?
    let disk: String?
    let ipAddress: String?
    let createdAt: String?
    let kernel: String?
    let homeMount: String?
    let nestedVirtualization: Bool?
    let isDefault: Bool?

    enum CodingKeys: String, CodingKey {
        case name, state, cpus, memory, disk, kernel
        case ipAddress, ipAddress2 = "ip", ipAddress3 = "address"
        case createdAt, createdAt2 = "created", createdAt3 = "creationDate"
        case homeMount = "homeMount", homeMount2 = "home-mount"
        case nestedVirtualization, isDefault = "default", isDefault2 = "isDefault"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        cpus = try c.decodeIfPresent(Int.self, forKey: .cpus)
        memory = try c.decodeIfPresent(String.self, forKey: .memory)
        disk = try c.decodeIfPresent(String.self, forKey: .disk)
        kernel = try c.decodeIfPresent(String.self, forKey: .kernel)
        ipAddress = try c.decodeIfPresent(String.self, forKey: .ipAddress)
            ?? c.decodeIfPresent(String.self, forKey: .ipAddress2)
            ?? c.decodeIfPresent(String.self, forKey: .ipAddress3)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
            ?? c.decodeIfPresent(String.self, forKey: .createdAt2)
            ?? c.decodeIfPresent(String.self, forKey: .createdAt3)
        homeMount = try c.decodeIfPresent(String.self, forKey: .homeMount)
            ?? c.decodeIfPresent(String.self, forKey: .homeMount2)
        nestedVirtualization = try c.decodeIfPresent(Bool.self, forKey: .nestedVirtualization)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault)
            ?? c.decodeIfPresent(Bool.self, forKey: .isDefault2)
    }
}
```

> This custom decoder tolerates several plausible key spellings; Phase H trims it to the real shape. (If two CodingKeys map to the same string Swift rejects it — the aliases above use distinct case names with distinct rawValues, which is allowed.)

- [ ] **Step 3b:** `OutputParser.swift` — replace `parseMachines` (~185) and add `parseMachine`:

```swift
    public static func parseMachines(_ data: Data) throws -> [MachineSummary] {
        try lossyList(data, decode: CLIMachineRecord.self).compactMap(Self.machine(from:))
    }

    /// Parses a single `machine inspect` object (the CLI emits one object, not an array).
    public static func parseMachine(_ data: Data) -> MachineSummary? {
        if let one = try? decoder.decode(CLIMachineRecord.self, from: data) {
            return machine(from: one)
        }
        return (try? parseMachines(data))?.first
    }

    private static func machine(from record: CLIMachineRecord) -> MachineSummary? {
        guard let name = record.name else { return nil }
        return MachineSummary(
            name: name, state: record.state, createdAt: record.createdAt,
            ipAddress: record.ipAddress, cpus: record.cpus, memory: record.memory,
            disk: record.disk, isDefault: record.isDefault ?? false,
            kernel: record.kernel, nestedVirtualization: record.nestedVirtualization,
            homeMount: record.homeMount)
    }
```

> `decoder` is the file-private `JSONDecoder` already used by `parseVersion`/`lossyList`. Confirm its name; if it's spelled differently, reuse the existing one.

- [ ] **Step 3c:** `CLICommand.swift` — after `listMachines()` (~190) add:

```swift
    public static func createMachine(_ config: MachineConfiguration) -> [String] {
        config.arguments
    }
    public static func setMachine(name: String?, settings: MachineSettings) -> [String] {
        settings.arguments(name: name)
    }
    public static func setDefaultMachine(id: String) -> [String] {
        ArgumentBuilder("machine", "set-default").adding(id).arguments
    }
    public static func stopMachine(id: String?) -> [String] {
        var b = ArgumentBuilder("machine", "stop")
        if let id, !id.isEmpty { b = b.adding(id) }
        return b.arguments
    }
    public static func deleteMachine(id: String) -> [String] {
        ArgumentBuilder("machine", "delete").adding(id).arguments
    }
    public static func inspectMachine(id: String?) -> [String] {
        var b = ArgumentBuilder("machine", "inspect")
        if let id, !id.isEmpty { b = b.adding(id) }
        return b.arguments   // NB: no --format; inspect emits JSON by default
    }
    public static func machineLogs(id: String?, tail: Int?, boot: Bool, follow: Bool) -> [String] {
        var b = ArgumentBuilder("machine", "logs")
        if boot { b = b.adding("--boot") }
        if follow { b = b.adding("--follow") }
        if let tail { b = b.adding("-n", String(tail)) }
        if let id, !id.isEmpty { b = b.adding(id) }
        return b.arguments
    }
```

> Verify `ArgumentBuilder.adding(_:_:)` variadic exists (it does: `adding(_ args: String...)`). `-n 100` is two tokens → `adding("-n", String(tail))`.

- [ ] **Step 3d:** `CLIContainerBackend.swift` — after `listMachines()` (~360) add (mirror `listNetworks`/`pruneNetworks` for `runChecked`/`runner`/`streamRaw` usage; confirm helper names against the file):

```swift
    public func inspectMachine(id: String?) async throws -> Parsed<MachineSummary> {
        let output = try await runChecked(CLICommand.inspectMachine(id: id))
        return Parsed(value: OutputParser.parseMachine(Data(output.stdout.utf8)), raw: output.stdout)
    }
    public func createMachine(_ config: MachineConfiguration)
        -> AsyncThrowingStream<OutputLine, Error>
    {
        streamRaw(CLICommand.createMachine(config))
    }
    public func setMachine(name: String?, settings: MachineSettings) async throws {
        _ = try await runChecked(CLICommand.setMachine(name: name, settings: settings))
    }
    public func setDefaultMachine(id: String) async throws {
        _ = try await runChecked(CLICommand.setDefaultMachine(id: id))
    }
    public func stopMachine(id: String?) async throws {
        _ = try await runChecked(CLICommand.stopMachine(id: id))
    }
    public func deleteMachine(id: String) async throws {
        _ = try await runChecked(CLICommand.deleteMachine(id: id))
    }
    public func fetchMachineLogs(id: String?, tail: Int?, boot: Bool) async throws -> [OutputLine] {
        let output = try await runChecked(
            CLICommand.machineLogs(id: id, tail: tail, boot: boot, follow: false))
        return output.stdout.split(separator: "\n", omittingEmptySubsequences: false)
            .map { OutputLine(source: .stdout, text: String($0)) }
    }
    public func followMachineLogs(id: String?, boot: Bool) -> AsyncThrowingStream<OutputLine, Error> {
        streamRaw(CLICommand.machineLogs(id: id, tail: nil, boot: boot, follow: true))
    }
```

- [ ] **Step 4: Run, expect PASS** — `make test` (A4+A5+A6 now compile & pass).
- [ ] **Step 5: Commit** — `feat(backend): machine port methods across protocol, MockBackend, and CLI adapter`.

---

## Phase B — Domain models

### Task B1: `OperationKind.machineCreate`

**Files:** Modify `Sources/CapsuleDomain/TaskCenter.swift:17-55`; Test `Tests/CapsuleUnitTests/TaskCenterTests.swift` (append, or create a focused test).

- [ ] **Step 1: Failing test**

```swift
    func test_machineCreate_kind_titleAndSymbol() {
        XCTAssertEqual(OperationKind.machineCreate.title, "Create Machine")
        XCTAssertFalse(OperationKind.machineCreate.symbolName.isEmpty)
    }
```

- [ ] **Step 2: FAIL.** **Step 3:** add `case machineCreate` to the enum, `case .machineCreate: return "Create Machine"` to `title`, and `case .machineCreate: return "cpu"` to `symbolName`. **Step 4: PASS.** **Step 5: Commit** — `feat(domain): add machineCreate OperationKind`.

---

### Task B2: `MachineState` enum

**Files:** Create `Sources/CapsuleDomain/Machine.swift` (start the file here); Test `Tests/CapsuleUnitTests/MachineStateTests.swift`.

**Interfaces:**
- Produces: `enum MachineState: String, Sendable, Equatable { case running, stopped, unknown }` with `init(raw: String?)` (case-insensitive; nil/empty/unrecognized → `.unknown`), `var isRunning: Bool`, `var label: String` (Title Case), `var symbolName: String`.

- [ ] **Step 1: Failing test**

```swift
//  MachineStateTests.swift  (+ header)
import XCTest
@testable import CapsuleDomain

final class MachineStateTests: XCTestCase {
    func test_parsing() {
        XCTAssertEqual(MachineState(raw: "running"), .running)
        XCTAssertEqual(MachineState(raw: "RUNNING"), .running)
        XCTAssertEqual(MachineState(raw: "stopped"), .stopped)
        XCTAssertEqual(MachineState(raw: nil), .unknown)
        XCTAssertEqual(MachineState(raw: "weird"), .unknown)
    }
    func test_isRunning_label() {
        XCTAssertTrue(MachineState.running.isRunning)
        XCTAssertEqual(MachineState.stopped.label, "Stopped")
    }
}
```

- [ ] **Step 2: FAIL.** **Step 3:** create `Machine.swift` with header + `import Foundation` and:

```swift
public enum MachineState: String, Sendable, Equatable {
    case running, stopped, unknown
    public init(raw: String?) {
        switch raw?.lowercased() {
        case "running": self = .running
        case "stopped", "stop", "off": self = .stopped
        default: self = .unknown
        }
    }
    public var isRunning: Bool { self == .running }
    public var label: String {
        switch self {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .unknown: return "Unknown"
        }
    }
    public var symbolName: String {
        switch self {
        case .running: return "play.circle.fill"
        case .stopped: return "stop.circle"
        case .unknown: return "questionmark.circle"
        }
    }
}
```

- [ ] **Step 4: PASS.** **Step 5: Commit** — `feat(domain): MachineState enum`.

---

### Task B3: `Machine` domain struct + `init(summary:)`

**Files:** Modify `Sources/CapsuleDomain/Machine.swift` (append); Test `Tests/CapsuleUnitTests/MachineTests.swift`.

**Interfaces:**
- Produces: `struct Machine: Sendable, Equatable, Identifiable { id:String, name:String, state:MachineState, isDefault:Bool, ipAddress:String?, cpus:Int?, memory:String?, disk:String?, homeMount:String?, kernel:String?, nestedVirtualization:Bool?, createdAt:Date? }` + memberwise init + `init(summary: MachineSummary)` (maps state via `MachineState(raw:)`, date via `Container.parseDate`).

- [ ] **Step 1: Failing test**

```swift
//  MachineTests.swift  (+ header)
import XCTest
@testable import CapsuleDomain
@testable import CapsuleBackend

final class MachineTests: XCTestCase {
    func test_fromSummary_mapsFields() {
        let s = MachineSummary(
            name: "dev", state: "running", createdAt: "2026-06-20T09:15:00Z",
            ipAddress: "192.168.66.2", cpus: 4, memory: "8G", disk: "20G", isDefault: true,
            homeMount: "rw")
        let m = Machine(summary: s)
        XCTAssertEqual(m.id, "dev")
        XCTAssertEqual(m.state, .running)
        XCTAssertTrue(m.isDefault)
        XCTAssertEqual(m.cpus, 4)
        XCTAssertNotNil(m.createdAt)
    }
}
```

- [ ] **Step 2: FAIL.** **Step 3:** append to `Machine.swift` (`import CapsuleBackend` at top):

```swift
public struct Machine: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var state: MachineState
    public var isDefault: Bool
    public var ipAddress: String?
    public var cpus: Int?
    public var memory: String?
    public var disk: String?
    public var homeMount: String?
    public var kernel: String?
    public var nestedVirtualization: Bool?
    public var createdAt: Date?

    public init(
        id: String, name: String, state: MachineState = .unknown, isDefault: Bool = false,
        ipAddress: String? = nil, cpus: Int? = nil, memory: String? = nil, disk: String? = nil,
        homeMount: String? = nil, kernel: String? = nil, nestedVirtualization: Bool? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id; self.name = name; self.state = state; self.isDefault = isDefault
        self.ipAddress = ipAddress; self.cpus = cpus; self.memory = memory; self.disk = disk
        self.homeMount = homeMount; self.kernel = kernel
        self.nestedVirtualization = nestedVirtualization; self.createdAt = createdAt
    }
}

extension Machine {
    public init(summary: MachineSummary) {
        self.init(
            id: summary.id, name: summary.name, state: MachineState(raw: summary.state),
            isDefault: summary.isDefault, ipAddress: summary.ipAddress, cpus: summary.cpus,
            memory: summary.memory, disk: summary.disk, homeMount: summary.homeMount,
            kernel: summary.kernel, nestedVirtualization: summary.nestedVirtualization,
            createdAt: summary.createdAt.flatMap(Container.parseDate))
    }
}
```

> Confirm `Container.parseDate` is `static` and `internal`/`public` to `CapsuleDomain` (the Network model uses it the same way).

- [ ] **Step 4: PASS.** **Step 5: Commit** — `feat(domain): Machine domain model`.

---

### Task B4: `MachineImagePreset` (create-wizard presets)

**Files:** Create `Sources/CapsuleDomain/MachineImagePreset.swift`; Test `Tests/CapsuleUnitTests/MachineImagePresetTests.swift`.

**Interfaces:**
- Produces: `struct MachineImagePreset: Sendable, Equatable, Identifiable { id:String{reference}, displayName:String, reference:String }` + `static let all: [MachineImagePreset]`.

- [ ] **Step 1: Failing test**

```swift
//  MachineImagePresetTests.swift  (+ header)
import XCTest
@testable import CapsuleDomain

final class MachineImagePresetTests: XCTestCase {
    func test_presets_nonEmpty_haveReferences() {
        XCTAssertFalse(MachineImagePreset.all.isEmpty)
        XCTAssertTrue(MachineImagePreset.all.allSatisfy { $0.reference.contains(":") })
        XCTAssertTrue(MachineImagePreset.all.contains { $0.reference.hasPrefix("alpine") })
    }
}
```

- [ ] **Step 2: FAIL.** **Step 3:** implement:

```swift
//  MachineImagePreset.swift  (+ header)
import Foundation

/// A curated distro/OCI image option for the create wizard. The wizard also offers a custom
/// reference, so this list is convenience, not a constraint.
public struct MachineImagePreset: Sendable, Equatable, Identifiable {
    public var id: String { reference }
    public var displayName: String
    public var reference: String
    public init(displayName: String, reference: String) {
        self.displayName = displayName; self.reference = reference
    }
    public static let all: [MachineImagePreset] = [
        .init(displayName: "Alpine 3.22", reference: "alpine:3.22"),
        .init(displayName: "Ubuntu 24.04", reference: "ubuntu:24.04"),
        .init(displayName: "Debian 12", reference: "debian:12"),
        .init(displayName: "Fedora 40", reference: "fedora:40"),
    ]
}
```

- [ ] **Step 4: PASS.** **Step 5: Commit** — `feat(domain): MachineImagePreset list`.

---

### Task B5: `MachineDraft` + `MachineSettingsDraft`

**Files:** Create `Sources/CapsuleDomain/MachineDraft.swift`; Test `Tests/CapsuleUnitTests/MachineDraftTests.swift`.

**Interfaces:**
- Produces: `struct MachineDraft: Sendable, Equatable { image:String="", name:String="", cpus:String="", memory:String="", homeMount:String="rw", setDefault:Bool=false, noBoot:Bool=false, arch:String="", os:String="", platform:String="" }`; `struct MachineSettingsDraft: Sendable, Equatable { cpus:String="", memory:String="", homeMount:String="rw" }` + `init(machine: Machine)` seeding from current values.

- [ ] **Step 1: Failing test**

```swift
//  MachineDraftTests.swift  (+ header)
import XCTest
@testable import CapsuleDomain

final class MachineDraftTests: XCTestCase {
    func test_draftDefaults() {
        let d = MachineDraft()
        XCTAssertEqual(d.homeMount, "rw")
        XCTAssertFalse(d.setDefault)
    }
    func test_settingsDraft_seedsFromMachine() {
        let m = Machine(id: "dev", name: "dev", cpus: 4, memory: "8G", homeMount: "ro")
        let s = MachineSettingsDraft(machine: m)
        XCTAssertEqual(s.cpus, "4")
        XCTAssertEqual(s.memory, "8G")
        XCTAssertEqual(s.homeMount, "ro")
    }
}
```

- [ ] **Step 2: FAIL.** **Step 3:** implement both structs (the settings-draft seed maps `cpus.map(String.init) ?? ""`, `memory ?? ""`, `homeMount ?? "rw"`). **Step 4: PASS.** **Step 5: Commit** — `feat(domain): machine create/settings drafts`.

---

### Task B6: `MachineValidation`

**Files:** Create `Sources/CapsuleDomain/MachineValidation.swift`; Test `Tests/CapsuleUnitTests/MachineValidationTests.swift`.

**Interfaces:**
- Produces: `enum MachineValidation` with `static func imageProblem(_:)->String?`, `static func cpusProblem(_:)->String?`, `static func memoryProblem(_:)->String?`, `static func homeMountProblem(_:)->String?`. Each returns nil when valid (empty cpus/memory = "use default" = valid for create/set), else a user message. memory matches `^\d+(\.\d+)?[MG]$` (case-insensitive). cpus = positive integer. homeMount ∈ {rw,ro,none}. image non-empty.

- [ ] **Step 1: Failing test**

```swift
//  MachineValidationTests.swift  (+ header)
import XCTest
@testable import CapsuleDomain

final class MachineValidationTests: XCTestCase {
    func test_image() {
        XCTAssertNotNil(MachineValidation.imageProblem(""))
        XCTAssertNil(MachineValidation.imageProblem("alpine:3.22"))
    }
    func test_cpus() {
        XCTAssertNil(MachineValidation.cpusProblem(""))       // empty → default
        XCTAssertNil(MachineValidation.cpusProblem("4"))
        XCTAssertNotNil(MachineValidation.cpusProblem("0"))
        XCTAssertNotNil(MachineValidation.cpusProblem("-2"))
        XCTAssertNotNil(MachineValidation.cpusProblem("x"))
    }
    func test_memory() {
        XCTAssertNil(MachineValidation.memoryProblem(""))     // empty → default
        XCTAssertNil(MachineValidation.memoryProblem("8G"))
        XCTAssertNil(MachineValidation.memoryProblem("512M"))
        XCTAssertNotNil(MachineValidation.memoryProblem("8"))
        XCTAssertNotNil(MachineValidation.memoryProblem("lots"))
    }
    func test_homeMount() {
        XCTAssertNil(MachineValidation.homeMountProblem("rw"))
        XCTAssertNotNil(MachineValidation.homeMountProblem("maybe"))
    }
}
```

- [ ] **Step 2: FAIL.** **Step 3:** implement (trim first; empty cpus/memory return nil; regex via `range(of:options:.regularExpression)`):

```swift
//  MachineValidation.swift  (+ header)
import Foundation

public enum MachineValidation {
    public static func imageProblem(_ image: String) -> String? {
        image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "An image reference is required (e.g. alpine:3.22)." : nil
    }
    public static func cpusProblem(_ cpus: String) -> String? {
        let t = cpus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        guard let n = Int(t), n > 0 else { return "CPUs must be a positive whole number." }
        return nil
    }
    public static func memoryProblem(_ memory: String) -> String? {
        let t = memory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return t.range(of: #"^\d+(\.\d+)?[MmGg]$"#, options: .regularExpression) != nil
            ? nil : "Memory must be a size like 2G or 512M."
    }
    public static func homeMountProblem(_ value: String) -> String? {
        ["rw", "ro", "none"].contains(value.lowercased()) ? nil
            : "Home mount must be rw, ro, or none."
    }
}
```

- [ ] **Step 4: PASS.** **Step 5: Commit** — `feat(domain): MachineValidation rules`.

---

### Task B7: `MachineBanner` (success-banner value type)

**Files:** Create `Sources/CapsuleDomain/MachineBanner.swift`; Test `Tests/CapsuleUnitTests/MachineBannerTests.swift`.

**Interfaces:**
- Produces: `struct MachineBanner: Sendable, Equatable, Identifiable` with `enum Kind { case created(name:String); case stopped(name:String); case implicitBoot(name:String); case madeDefault(name:String, previous:String?) }`, `var kind:Kind`, stable `id`, `var title:String`, `var message:String`. (Restart-required is tracked separately via `pendingRestart`, not a banner.)

- [ ] **Step 1: Failing test**

```swift
//  MachineBannerTests.swift  (+ header)
import XCTest
@testable import CapsuleDomain

final class MachineBannerTests: XCTestCase {
    func test_madeDefault_hasUndoableMessage() {
        let b = MachineBanner(kind: .madeDefault(name: "dev", previous: "old"))
        XCTAssertTrue(b.message.contains("dev"))
        XCTAssertFalse(b.id.isEmpty)
    }
    func test_implicitBoot_mentionsBooting() {
        XCTAssertTrue(MachineBanner(kind: .implicitBoot(name: "dev")).message.lowercased()
            .contains("boot"))
    }
}
```

- [ ] **Step 2: FAIL.** **Step 3:** implement with `title`/`message` per kind (created → "Machine created"; stopped → "Machine stopped"; implicitBoot → "Capsule is booting \(name) …"; madeDefault → "\(name) is now the default machine."). `id` = string of the kind. **Step 4: PASS.** **Step 5: Commit** — `feat(domain): MachineBanner value type`.

---

### Task B8: `ConfirmationRequest.deleteMachine`

**Files:** Modify `Sources/CapsuleDomain/Confirmation.swift` (add `.deleteMachine` to `ConfirmationKind` ~24 + builder); Test `Tests/CapsuleUnitTests/ConfirmationMachineTests.swift`.

**Interfaces:**
- Produces: `ConfirmationKind.deleteMachine`; `static func deleteMachine(name: String) -> ConfirmationRequest` (always returns a request; message warns persistent storage is destroyed).

- [ ] **Step 1: Failing test**

```swift
//  ConfirmationMachineTests.swift  (+ header)
import XCTest
@testable import CapsuleDomain

final class ConfirmationMachineTests: XCTestCase {
    func test_deleteMachine_warnsPersistentStorage() {
        let r = ConfirmationRequest.deleteMachine(name: "dev")
        XCTAssertEqual(r.kind, .deleteMachine)
        XCTAssertEqual(r.targetIDs, ["dev"])
        XCTAssertTrue(r.message.lowercased().contains("persistent"))
        XCTAssertEqual(r.confirmTitle, "Delete")
    }
}
```

- [ ] **Step 2: FAIL.** **Step 3:** add `case deleteMachine` to `ConfirmationKind`; add builder:

```swift
    // MARK: Machines (Milestone 9)

    /// Deleting a machine always confirms — it permanently removes the machine's persistent
    /// storage (home directory and disk). There is no undo.
    public static func deleteMachine(name: String) -> ConfirmationRequest {
        ConfirmationRequest(
            title: "Delete machine?",
            message: "Deleting \(name) permanently removes its persistent storage "
                + "(home directory and disk). This cannot be undone.",
            confirmTitle: "Delete", targetIDs: [name], kind: .deleteMachine)
    }
```

- [ ] **Step 4: PASS.** **Step 5: Commit** — `feat(domain): deleteMachine confirmation`.

---

### Task B9: `MachineBrowserModel`

**Files:** Create `Sources/CapsuleDomain/MachineBrowserModel.swift`; Test `Tests/CapsuleUnitTests/MachineBrowserModelTests.swift`. Mirror `NetworkBrowserModel` (no attachment index — machines have none).

**Interfaces:**
- Produces: `enum MachineLoadState { idle, loading, loaded, unavailable(ErrorDetail) }`; `struct MachineInspection { value:Machine?, rawJSON:String }`; `@MainActor @Observable final class MachineBrowserModel` with `allMachines:[Machine]`, `loadState`, `searchText`, `selection:Set<Machine.ID>`, `rows`, `selectedMachines`, `defaultMachine:Machine?`, `isEmptyButHealthy`, `noMatches`, `func refresh() async`, `func inspect(id: String) async -> MachineInspection`, and the standard `init(backend:normalize:onActivity:)`.

- [ ] **Step 1: Failing test**

```swift
//  MachineBrowserModelTests.swift  (+ header)
import XCTest
@testable import CapsuleDomain
@testable import CapsuleBackend

@MainActor
final class MachineBrowserModelTests: XCTestCase {
    func test_refresh_loaded_sortsAndStampsDefault() async {
        let mock = MockBackend(machines: MockBackend.sampleMachines)
        let m = MachineBrowserModel(backend: mock)
        await m.refresh()
        XCTAssertEqual(m.loadState, .loaded)
        XCTAssertEqual(m.rows.map(\.name), ["builder", "default"]) // name-sorted
        XCTAssertEqual(m.defaultMachine?.name, "default")
    }
    func test_refresh_empty_isHealthyEmpty() async {
        let m = MachineBrowserModel(backend: MockBackend(machines: []))
        await m.refresh()
        XCTAssertTrue(m.isEmptyButHealthy)
    }
    func test_refresh_failure_unavailable() async {
        let mock = MockBackend(machines: [])
        mock.failure = .nonZeroExit(command: "machine list", code: 1, stderr: "boom")
        let m = MachineBrowserModel(backend: mock)
        await m.refresh()
        if case .unavailable = m.loadState {} else { XCTFail("expected unavailable") }
    }
    func test_inspect_returnsRaw() async {
        let mock = MockBackend(machines: [MachineSummary(name: "dev")])
        let m = MachineBrowserModel(backend: mock)
        let insp = await m.inspect(id: "dev")
        XCTAssertEqual(insp.value?.name, "dev")
    }
}
```

- [ ] **Step 2: FAIL.** **Step 3:** implement mirroring `NetworkBrowserModel` (replace `inspect(name:)`→`inspect(id:)` calling `backend.inspectMachine(id:)`; `refresh()` calls `backend.listMachines()`, maps `Machine(summary:)`, sorts not required in storage but `rows` sorts by name; add `defaultMachine` = `allMachines.first { $0.isDefault }`; `matchesSearch` checks name + state.label). **Step 4: PASS.** **Step 5: Commit** — `feat(domain): MachineBrowserModel read surface`.

---

### Task B10: `MachineActionsModel` — create + validation accessors + command preview

**Files:** Create `Sources/CapsuleDomain/MachineActionsModel.swift`; Test `Tests/CapsuleUnitTests/MachineActionsModelCreateTests.swift`.

**Interfaces:**
- Produces: `@MainActor @Observable final class MachineActionsModel` with stored: `busy:Set<String>`, `notice:LifecycleNotice?`, `confirmation:ConfirmationRequest?`, `banner:MachineBanner?`, `pendingRestart:Set<String>`. Injected closures: `backend`, `normalize`, `onActivity`, `reloadList`, `currentState: @MainActor (String) -> MachineState`, `terminalAvailable`, `copyCommand`, `launchTerminal`, `taskCenter: TaskCenter?`, plus internal `previousDefault: String?`.
  - This task implements: `init(...)`, `configuration(from: MachineDraft) -> MachineConfiguration`, `commandPreview(for: MachineDraft) -> String`, `createProblem(_ draft) -> String?`, `canCreate(_ draft) -> Bool`, `func create(draft:) async -> Bool` (runs through `taskCenter.runStreaming(kind:.machineCreate)` when present, else drains the stream inline; reloads on success; sets `banner = .created`). Later tasks append set/default/stop/delete/shell.

- [ ] **Step 1: Failing test**

```swift
//  MachineActionsModelCreateTests.swift  (+ header)
import XCTest
@testable import CapsuleDomain
@testable import CapsuleBackend

@MainActor
final class MachineActionsModelCreateTests: XCTestCase {
    private func make(_ mock: MockBackend) -> MachineActionsModel {
        MachineActionsModel(backend: mock, reloadList: {})
    }
    func test_commandPreview_reflectsDraft() {
        let a = make(MockBackend(machines: []))
        var d = MachineDraft(); d.image = "alpine:3.22"; d.name = "dev"; d.cpus = "4"
        XCTAssertEqual(a.commandPreview(for: d),
            "container machine create --name dev --cpus 4 --home-mount rw alpine:3.22")
    }
    func test_canCreate_requiresValidImage() {
        let a = make(MockBackend(machines: []))
        var d = MachineDraft()
        XCTAssertFalse(a.canCreate(d))
        d.image = "alpine:3.22"
        XCTAssertTrue(a.canCreate(d))
        d.cpus = "x"
        XCTAssertFalse(a.canCreate(d))
    }
    func test_create_succeeds_setsBanner() async {
        let mock = MockBackend(machines: [])
        let a = make(mock)
        var d = MachineDraft(); d.image = "alpine:3.22"; d.name = "dev"
        let ok = await a.create(draft: d)
        XCTAssertTrue(ok)
        XCTAssertEqual(mock.lastCreatedMachine?.image, "alpine:3.22")
        if case .created = a.banner?.kind {} else { XCTFail("expected created banner") }
    }
}
```

- [ ] **Step 2: FAIL.** **Step 3:** implement. Key bodies:

```swift
    public func configuration(from draft: MachineDraft) -> MachineConfiguration {
        func trimmed(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t
        }
        return MachineConfiguration(
            image: draft.image.trimmingCharacters(in: .whitespacesAndNewlines),
            name: trimmed(draft.name),
            cpus: trimmed(draft.cpus).flatMap(Int.init),
            memory: trimmed(draft.memory),
            homeMount: trimmed(draft.homeMount),
            arch: trimmed(draft.arch), os: trimmed(draft.os), platform: trimmed(draft.platform),
            setDefault: draft.setDefault, noBoot: draft.noBoot)
    }
    public func commandPreview(for draft: MachineDraft) -> String {
        "container " + configuration(from: draft).arguments.joined(separator: " ")
    }
    public func createProblem(_ draft: MachineDraft) -> String? {
        MachineValidation.imageProblem(draft.image)
            ?? MachineValidation.cpusProblem(draft.cpus)
            ?? MachineValidation.memoryProblem(draft.memory)
            ?? MachineValidation.homeMountProblem(draft.homeMount)
    }
    public func canCreate(_ draft: MachineDraft) -> Bool { createProblem(draft) == nil }

    @discardableResult
    public func create(draft: MachineDraft) async -> Bool {
        if let problem = createProblem(draft) {
            notice = LifecycleNotice(detail: ErrorDetail(title: "Can\u{2019}t create machine",
                explanation: problem, recoveryActions: []))
            return false
        }
        let config = configuration(from: draft)
        let name = config.name ?? config.image
        if let taskCenter {
            let task = taskCenter.runStreaming(
                kind: .machineCreate, title: "Create machine \(name)",
                onSuccess: { [weak self] in await self?.reloadList() }
            ) { [backend] in backend.createMachine(config) }
            await task.wait()
            guard case .succeeded = task.state else { return false }
        } else {
            do { for try await _ in backend.createMachine(config) {} }
            catch { notice = LifecycleNotice(detail: normalize(error).detail); return false }
            await reloadList()
        }
        onActivity("Created machine \u{201c}\(name)\u{201d}.")
        banner = MachineBanner(kind: .created(name: name))
        return true
    }
```

> Use the full `init` with all closures (default empty, matching `ContainerLifecycleModel`'s pattern). `ErrorDetail` initializer: confirm its label names against `ErrorDetail.swift` (title/explanation/recoveryActions).

- [ ] **Step 4: PASS.** **Step 5: Commit** — `feat(domain): MachineActionsModel create + validation`.

---

### Task B11: `MachineActionsModel` — set + restart-required tracking

**Files:** Modify `MachineActionsModel.swift`; Test `Tests/CapsuleUnitTests/MachineActionsModelSetTests.swift`.

**Interfaces:**
- Produces: `func settingsPreview(name:String?, draft:MachineSettingsDraft) -> String`, `func settingsProblem(_:) -> String?`, `func apply(settings draft: MachineSettingsDraft, to name: String) async -> Bool` (calls `backend.setMachine`; on success inserts `name` into `pendingRestart`, sets `onActivity`), `func restartRequired(_ name:String) -> Bool`, `func clearRestart(_ name:String)`.

- [ ] **Step 1: Failing test**

```swift
//  MachineActionsModelSetTests.swift  (+ header)
import XCTest
@testable import CapsuleDomain
@testable import CapsuleBackend

@MainActor
final class MachineActionsModelSetTests: XCTestCase {
    func test_apply_recordsSettings_marksRestartRequired() async {
        let mock = MockBackend(machines: [MachineSummary(name: "dev", cpus: 2)])
        let a = MachineActionsModel(backend: mock, reloadList: {})
        var d = MachineSettingsDraft(); d.cpus = "8"; d.memory = "16G"
        let ok = await a.apply(settings: d, to: "dev")
        XCTAssertTrue(ok)
        XCTAssertEqual(mock.lastMachineSettings?.settings.cpus, 8)
        XCTAssertTrue(a.restartRequired("dev"))
    }
    func test_settingsProblem_invalidCpus() {
        let a = MachineActionsModel(backend: MockBackend(machines: []), reloadList: {})
        var d = MachineSettingsDraft(); d.cpus = "0"
        XCTAssertNotNil(a.settingsProblem(d))
    }
}
```

- [ ] **Step 2: FAIL.** **Step 3:** implement:

```swift
    private func settings(from draft: MachineSettingsDraft) -> MachineSettings {
        func trimmed(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t
        }
        return MachineSettings(
            cpus: trimmed(draft.cpus).flatMap(Int.init), memory: trimmed(draft.memory),
            homeMount: trimmed(draft.homeMount))
    }
    public func settingsProblem(_ draft: MachineSettingsDraft) -> String? {
        MachineValidation.cpusProblem(draft.cpus)
            ?? MachineValidation.memoryProblem(draft.memory)
            ?? MachineValidation.homeMountProblem(draft.homeMount)
    }
    public func settingsPreview(name: String?, draft: MachineSettingsDraft) -> String {
        "container " + settings(from: draft).arguments(name: name).joined(separator: " ")
    }
    @discardableResult
    public func apply(settings draft: MachineSettingsDraft, to name: String) async -> Bool {
        if let problem = settingsProblem(draft) {
            notice = LifecycleNotice(detail: ErrorDetail(
                title: "Can\u{2019}t update settings", explanation: problem, recoveryActions: []))
            return false
        }
        busy.insert(name); defer { busy.remove(name) }
        do {
            try await backend.setMachine(name: name, settings: settings(from: draft))
            await reloadList()
            pendingRestart.insert(name)
            onActivity("Updated \u{201c}\(name)\u{201d}; restart to apply.")
            return true
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail); return false
        }
    }
    public func restartRequired(_ name: String) -> Bool { pendingRestart.contains(name) }
    public func clearRestart(_ name: String) { pendingRestart.remove(name) }
```

- [ ] **Step 4: PASS.** **Step 5: Commit** — `feat(domain): machine set + restart-required tracking`.

---

### Task B12: `MachineActionsModel` — set-default + one-click revert

**Files:** Modify `MachineActionsModel.swift`; Test `Tests/CapsuleUnitTests/MachineActionsModelDefaultTests.swift`.

**Interfaces:**
- Produces: `func makeDefault(_ name:String, previousDefault:String?) async`, `func revertDefault() async` (re-sets `previousDefault` recorded by the last `makeDefault`). `makeDefault` sets `banner = .madeDefault(name:previous:)`.

- [ ] **Step 1: Failing test**

```swift
//  MachineActionsModelDefaultTests.swift  (+ header)
import XCTest
@testable import CapsuleDomain
@testable import CapsuleBackend

@MainActor
final class MachineActionsModelDefaultTests: XCTestCase {
    func test_makeDefault_thenRevert() async {
        let mock = MockBackend(machines: [
            MachineSummary(name: "a", isDefault: true), MachineSummary(name: "b")])
        let a = MachineActionsModel(backend: mock, reloadList: {})
        await a.makeDefault("b", previousDefault: "a")
        XCTAssertEqual(mock.lastSetDefaultID, "b")
        if case .madeDefault = a.banner?.kind {} else { XCTFail("banner") }
        await a.revertDefault()
        XCTAssertEqual(mock.lastSetDefaultID, "a")
    }
}
```

- [ ] **Step 2: FAIL.** **Step 3:** implement:

```swift
    @discardableResult
    public func makeDefault(_ name: String, previousDefault: String?) async -> Bool {
        busy.insert(name); defer { busy.remove(name) }
        do {
            try await backend.setDefaultMachine(id: name)
            self.previousDefault = previousDefault
            await reloadList()
            onActivity("Made \u{201c}\(name)\u{201d} the default machine.")
            banner = MachineBanner(kind: .madeDefault(name: name, previous: previousDefault))
            return true
        } catch { notice = LifecycleNotice(detail: normalize(error).detail); return false }
    }
    public func revertDefault() async {
        guard let prev = previousDefault else { return }
        do {
            try await backend.setDefaultMachine(id: prev)
            await reloadList()
            onActivity("Reverted default machine to \u{201c}\(prev)\u{201d}.")
            banner = nil
        } catch { notice = LifecycleNotice(detail: normalize(error).detail) }
    }
```

- [ ] **Step 4: PASS.** **Step 5: Commit** — `feat(domain): machine set-default with revert`.

---

### Task B13: `MachineActionsModel` — stop + delete

**Files:** Modify `MachineActionsModel.swift`; Test `Tests/CapsuleUnitTests/MachineActionsModelLifecycleTests.swift`.

**Interfaces:**
- Produces: `func stop(_ name:String) async` (calls `backend.stopMachine`; clears `pendingRestart`; sets `banner = .stopped`); `func delete(_ name:String) async` (calls `backend.deleteMachine`; clears `pendingRestart`; `onActivity`).

- [ ] **Step 1: Failing test**

```swift
//  MachineActionsModelLifecycleTests.swift  (+ header)
import XCTest
@testable import CapsuleDomain
@testable import CapsuleBackend

@MainActor
final class MachineActionsModelLifecycleTests: XCTestCase {
    func test_stop_setsBanner_clearsRestart() async {
        let mock = MockBackend(machines: [MachineSummary(name: "dev", state: "running")])
        let a = MachineActionsModel(backend: mock, reloadList: {})
        a.pendingRestart.insert("dev")
        await a.stop("dev")
        XCTAssertEqual(mock.lastStoppedMachine, "dev")
        XCTAssertFalse(a.restartRequired("dev"))
        if case .stopped = a.banner?.kind {} else { XCTFail("banner") }
    }
    func test_delete_removes() async {
        let mock = MockBackend(machines: [MachineSummary(name: "dev")])
        let a = MachineActionsModel(backend: mock, reloadList: {})
        await a.delete("dev")
        XCTAssertEqual(mock.lastDeletedMachine, "dev")
    }
}
```

> `pendingRestart` must be settable by the test — declare it `public internal(set) var pendingRestart: Set<String> = []` OR `public var`. Use `public internal(set)` and have the test in the same module (`@testable import`) set it; if `internal(set)` blocks the test, use `public private(set)` plus seed via `apply(...)`. Simplest: declare `public var pendingRestart: Set<String> = []`.

- [ ] **Step 2: FAIL.** **Step 3:** implement (mirror `delete(name:)` from `NetworkActionsModel`; `stop` clears restart + sets banner). **Step 4: PASS.** **Step 5: Commit** — `feat(domain): machine stop + delete`.

---

### Task B14: `MachineActionsModel` — shell + implicit-boot detection + restart-now

**Files:** Modify `MachineActionsModel.swift`; Test `Tests/CapsuleUnitTests/MachineActionsModelShellTests.swift`.

**Interfaces:**
- Produces:
  - `func openShell(name: String)` — builds `["container","machine","run","-it","-n",name]` (omit `-n name` when name empty), routes via `launchTerminal` when `terminalAvailable()` else `copyCommand`; if `currentState(name) != .running` sets `banner = .implicitBoot(name:)`.
  - `func shellArgv(name: String) -> [String]` (pure, for tests/menu).
  - `func restartNow(_ name: String) async` — `stop` then re-open shell (boot) — clears `pendingRestart`.

- [ ] **Step 1: Failing test**

```swift
//  MachineActionsModelShellTests.swift  (+ header)
import XCTest
@testable import CapsuleDomain
@testable import CapsuleBackend

@MainActor
final class MachineActionsModelShellTests: XCTestCase {
    func test_shellArgv() {
        let a = MachineActionsModel(backend: MockBackend(machines: []), reloadList: {})
        XCTAssertEqual(a.shellArgv(name: "dev"), ["container", "machine", "run", "-it", "-n", "dev"])
    }
    func test_openShell_stopped_setsImplicitBootBanner_andLaunches() {
        var launched: [String]?
        let a = MachineActionsModel(
            backend: MockBackend(machines: []), reloadList: {},
            currentState: { _ in .stopped }, terminalAvailable: { true },
            launchTerminal: { launched = $0.argv })
        a.openShell(name: "dev")
        XCTAssertEqual(launched, ["container", "machine", "run", "-it", "-n", "dev"])
        if case .implicitBoot = a.banner?.kind {} else { XCTFail("implicit boot banner") }
    }
    func test_openShell_running_noImplicitBootBanner() {
        let a = MachineActionsModel(
            backend: MockBackend(machines: []), reloadList: {},
            currentState: { _ in .running }, terminalAvailable: { true }, launchTerminal: { _ in })
        a.openShell(name: "dev")
        XCTAssertNil(a.banner)
    }
}
```

- [ ] **Step 2: FAIL.** **Step 3:** implement:

```swift
    public func shellArgv(name: String) -> [String] {
        var argv = ["container", "machine", "run", "-it"]
        if !name.isEmpty { argv += ["-n", name] }
        return argv
    }
    public func openShell(name: String) {
        if currentState(name) != .running {
            banner = MachineBanner(kind: .implicitBoot(name: name))
        }
        let request = TerminalRequest(
            containerID: nil, title: "Machine \u{00b7} \(name)", argv: shellArgv(name: name),
            kind: .execShell)
        if terminalAvailable() { launchTerminal(request) } else { copyCommand(request.argv) }
    }
    public func restartNow(_ name: String) async {
        await stop(name)
        clearRestart(name)
        openShell(name: name)   // machine run boots it again
    }
```

> Confirm `TerminalRequest` init label order against `TerminalRequest.swift` (the lifecycle model uses `TerminalRequest(containerID:title:argv:kind:)`). `kind: .execShell` must exist on `TerminalRequest.Kind`.

- [ ] **Step 4: PASS.** **Step 5: Commit** — `feat(domain): machine shell + implicit-boot detection`.
- [ ] **Step 6: Cleanup check** — grep for `openMachineShell` usages: `grep -rn openMachineShell Sources`. If `ContainerLifecycleModel.openMachineShell` is unreferenced, remove it (now superseded by `MachineActionsModel.openShell`); if referenced, leave it. Commit separately if changed.

---

### Task B15: `LogSource` seam in `LogsModel`

**Files:** Modify `Sources/CapsuleDomain/LogsModel.swift`; Test `Tests/CapsuleUnitTests/LogsModelSourceTests.swift` (and confirm existing `LogsModelTests` still pass).

**Interfaces:**
- Produces: `struct LogSource: Sendable { var follow: @Sendable (_ id:String,_ boot:Bool)->AsyncThrowingStream<OutputLine,Error>; var fetch: @Sendable (_ id:String,_ tail:Int?,_ boot:Bool) async throws -> [OutputLine]; static func container(_ backend) -> LogSource; static func machine(_ backend) -> LogSource }`; new `LogsModel.init(source: LogSource)`; existing `init(backend:)` becomes `self.init(source: .container(backend))`. `start(id:)` unchanged signature, now routes through `source`.

- [ ] **Step 1: Failing test**

```swift
//  LogsModelSourceTests.swift  (+ header)
import XCTest
@testable import CapsuleDomain
@testable import CapsuleBackend

@MainActor
final class LogsModelSourceTests: XCTestCase {
    func test_machineSource_snapshot() async {
        let mock = MockBackend(machines: [MachineSummary(name: "dev")])
        let model = LogsModel(source: .machine(mock))
        model.follow = false
        model.boot = true
        model.start(id: "dev")
        await model.waitForLoad()
        XCTAssertFalse(model.lines.isEmpty)
    }
    func test_containerSource_backCompat() async {
        let model = LogsModel(backend: MockBackend())   // existing init still works
        model.follow = false
        model.start(id: "a1b2c3d4")
        await model.waitForLoad()
        XCTAssertFalse(model.lines.isEmpty)
    }
}
```

- [ ] **Step 2: FAIL.** **Step 3:** refactor `LogsModel`:
  - Add the `LogSource` struct (with `static func container`/`machine`).
  - Replace stored `private let backend` with `private let source: LogSource`.
  - `init(source:)` primary; `convenience? ` — Swift structs/classes: add `public init(source: LogSource) { self.source = source }` and `public init(backend: any ContainerBackend) { self.init(source: .container(backend)) }`.
  - In `start(id:)`, replace `backend.followLogs(container: id)` → `source.follow(id, boot)` and `backend.fetchLogs(container: id, tail: tail, boot: boot)` → `source.fetch(id, tail, boot)`.

```swift
public struct LogSource: Sendable {
    public var follow: @Sendable (_ id: String, _ boot: Bool) -> AsyncThrowingStream<OutputLine, Error>
    public var fetch: @Sendable (_ id: String, _ tail: Int?, _ boot: Bool) async throws -> [OutputLine]
    public init(
        follow: @escaping @Sendable (String, Bool) -> AsyncThrowingStream<OutputLine, Error>,
        fetch: @escaping @Sendable (String, Int?, Bool) async throws -> [OutputLine]
    ) { self.follow = follow; self.fetch = fetch }

    public static func container(_ backend: any ContainerBackend) -> LogSource {
        LogSource(
            follow: { id, _ in backend.followLogs(container: id) },
            fetch: { id, tail, boot in try await backend.fetchLogs(container: id, tail: tail, boot: boot) })
    }
    public static func machine(_ backend: any ContainerBackend) -> LogSource {
        LogSource(
            follow: { id, boot in backend.followMachineLogs(id: id, boot: boot) },
            fetch: { id, tail, boot in try await backend.fetchMachineLogs(id: id, tail: tail, boot: boot) })
    }
}
```

- [ ] **Step 4: PASS** — `make test` (existing LogsModel tests + new ones). **Step 5: Commit** — `refactor(domain): LogSource seam for container+machine logs`.

---

## Phase C — Composition-root wiring (renders the list)

### Task C1: Construct + thread `MachineBrowserModel` and `MachineActionsModel`; route `ContentColumnView`

**Files:**
- Modify: `Sources/CapsuleApp/AppEnvironment.swift` (property, init param, `live()` construction, return)
- Modify: `Sources/CapsuleApp/CapsuleScene.swift` (`@State` + init + pass to RootView)
- Modify: `Sources/CapsuleUI/RootView.swift`, `AppShellView.swift` (property + init param + pass-through)
- Modify: `Sources/CapsuleUI/ContentColumnView.swift` (`.machines` case → `MachineListView`)
- Create: `Sources/CapsuleUI/MachineListView.swift` (minimal placeholder body for now — real table in D1)

**Interfaces:**
- Consumes: B9 `MachineBrowserModel`, B10–B14 `MachineActionsModel`.
- Produces: `environment.machineBrowserModel`, `environment.machineActionsModel`; a `MachineListView(model:actions:)` initializer.

> This task is build-gated (no unit test — UI wiring). Verify with `make build` + `make app` and the arch guard.

- [ ] **Step 1:** In `AppEnvironment.live()`, after the `networkActionsModel` block, construct (mirror the network pair; wire `launchTerminal`/`copyCommand`/`terminalAvailable` from the same helpers the lifecycle model uses, and `taskCenter`):

```swift
let machineBrowserModel = MachineBrowserModel(
    backend: backend, normalize: { ErrorNormalizer.normalize($0) },
    onActivity: { shell.appendActivity($0) })
let machineActionsModel = MachineActionsModel(
    backend: backend, normalize: { ErrorNormalizer.normalize($0) },
    onActivity: { shell.appendActivity($0) },
    reloadList: { await machineBrowserModel.refresh() },
    currentState: { name in
        machineBrowserModel.allMachines.first { $0.name == name }?.state ?? .unknown },
    terminalAvailable: { terminalSurfaceAvailable() },
    copyCommand: copyCommandToClipboard,
    launchTerminal: { shell.openTerminal($0) },
    taskCenter: taskCenter)
```

> Match the exact spellings of the existing helpers in `live()` (`ErrorNormalizer.normalize`, `shell.appendActivity`, `copyCommandToClipboard`, `shell.openTerminal`, the terminal-available predicate, and `taskCenter`). Read the network/lifecycle construction in the file and copy those references verbatim.

- [ ] **Step 2:** Add `public var machineBrowserModel: MachineBrowserModel` and `public var machineActionsModel: MachineActionsModel` to the `AppEnvironment` struct, its `init`, and the `return AppEnvironment(...)`.
- [ ] **Step 3:** Thread both through `CapsuleScene` (`@State`), `RootView`, `AppShellView` to `ContentColumnView` (add stored props + init params at each hop — mirror how `networkBrowserModel`/`networkActionsModel` are threaded; grep `networkBrowserModel` across `Sources/CapsuleApp` + `Sources/CapsuleUI` to find every hop).
- [ ] **Step 4:** Create `MachineListView.swift` minimal:

```swift
//  MachineListView.swift  (+ header)
import CapsuleDomain
import SwiftUI

struct MachineListView: View {
    @Bindable var model: MachineBrowserModel
    let actions: MachineActionsModel
    var body: some View {
        Text("Machines").task { await model.refresh() }
    }
}
```

- [ ] **Step 5:** In `ContentColumnView.runningContent`, add before `default:`:

```swift
        case .machines:
            MachineListView(model: machineBrowserModel, actions: machineActionsModel)
```

(add the two stored props to `ContentColumnView` and pass them from `AppShellView`).

- [ ] **Step 6: Verify** — `make build && make arch && make app`. Launch is optional here. **Commit** — `feat(app): wire machine models through composition root`.

---

## Phase D — List + Inspector UI

### Task D1: `MachineListView` — Table, load states, search, toolbar, context menu

**Files:** Modify `Sources/CapsuleUI/MachineListView.swift`. Mirror `NetworkListView.swift` exactly for structure (load-state switch, `Table(model.rows, selection:)`, `.searchable`, `.toolbar`, `.contextMenu(forSelectionType:)`, `enum MachineSheet: Identifiable`).

**Columns:** lock-free; `Default` (star `Image(systemName:"star.fill")` when `machine.isDefault`, width 18) · `Name` · `State` (`Label(machine.state.label, systemImage: machine.state.symbolName)`) · `CPUs` (`machine.cpus.map(String.init) ?? "—"`) · `Memory` (`machine.memory ?? "—"`) · `IP` (monospaced, `?? "—"`) · `Created` (`.relative` or "—").

**Toolbar:** `Create` (`activeSheet = .create`), `Refresh` (`await model.refresh()`).

**Context menu (`rowMenu(for ids:)`):** single selection → `Open Shell` (`actions.openShell(name:)`), `Inspect` (set selection), `View Logs` (`activeSheet = .logs(name)`), `Settings…` (`activeSheet = .settings(name)`), Divider, `Make Default` (disabled if already default; `Task { await actions.makeDefault(name, previousDefault: model.defaultMachine?.name) }`), `Stop` (disabled if not running; `Task { await actions.stop(name) }`), Divider, `Delete…` (destructive → `activeSheet = .confirm(.deleteMachine(name:))`).

**Sheets enum:** `case create; case settings(String); case logs(String); case confirm(ConfirmationRequest)` with stable `id`. `performConfirmed` handles `.deleteMachine` → `Task { await actions.delete(name) }`.

- [ ] **Step 1:** Replace the placeholder body with the full mirror of `NetworkListView` adapted to the columns/menu above. Reuse `ConfirmationSheet` for `.confirm`. The `.create`/`.settings`/`.logs` sheet cases present views built in D-phase/E/F/G — for D1, stub `.settings`/`.logs` to `EmptyView()`/`Text` placeholders if those views don't exist yet (they're added in later tasks); wire `.create` only once `CreateMachineSheet` exists (Task E1). To keep the build green now, present only `.create` (guarded) — simplest: implement the table + toolbar + context menu, and make `activeSheet` cases that lack a view yet render a temporary `Text("…")`. Replace as each sheet lands.
- [ ] **Step 2: Verify** — `make build && make app`, launch with `make run` and confirm the table renders with `MockBackend.sampleMachines` (preview) showing the default star + state. **Commit** — `feat(ui): MachineListView table, search, toolbar, context menu`.

> NOTE: provide a `#Preview` using `MachineBrowserModel(backend: MockBackend(machines: MockBackend.sampleMachines))` — but `CapsuleUI` must not import `CapsuleBackend`. Check how `NetworkListView`'s preview handles this (previews may live where Backend is importable, or use a domain-level seed). Follow the exact pattern `NetworkListView` uses; do not add a Backend import to a UI file.

---

### Task D2: `MachineInspectorView` — Summary + Raw JSON

**Files:** Create `Sources/CapsuleUI/MachineInspectorView.swift`. Mirror `NetworkInspectorView.swift` (TabView Summary/Raw, `.task(id: model.selection) { await loadRaw() }`, `copyableField`, multi-selection placeholder).

**Summary fields:** Name; State (`Label(state.label, systemImage:)`); Default (`Label("Default", systemImage:"star.fill")` only when `isDefault`); IP (copyable); CPUs; Memory; Disk; Home mount; Created (`.dateTime`); **read-only Kernel** (only when `machine.kernel != nil`); **Nested virtualization** (only when `machine.nestedVirtualization != nil`, render Yes/No). Add a **"Restart required" banner** at the top of the summary when `actions.restartRequired(machine.name)` — prominent (yellow background, `exclamationmark.triangle.fill`) with a **Restart Now** button (`Task { await actions.restartNow(machine.name) }`) and a **Dismiss** that calls `actions.clearRestart(name)`.

**Raw tab:** `await model.inspect(id: machine.name)`, pretty-print via `JSONPrettyPrinter.prettyPrint`.

**Interfaces:** `MachineInspectorView(model: MachineBrowserModel, actions: MachineActionsModel)`. Wire it into the inspector column where `NetworkInspectorView` is dispatched (grep `NetworkInspectorView` in `InspectorView.swift`/`ContentColumnView`/`AppShellView` and add a `.machines` branch).

- [ ] **Step 1:** Implement the view. **Step 2:** Wire into the inspector dispatch (find where the right-hand inspector switches on `SidebarSection`; add `.machines` → `MachineInspectorView`). **Step 3: Verify** — `make build && make app && make run`; select a machine, confirm Summary + Raw render and the restart banner appears after a `set`. **Commit** — `feat(ui): MachineInspectorView with restart-required banner`.

---

## Phase E — Create wizard

### Task E1: `CreateMachineSheet` (the wizard)

**Files:** Create `Sources/CapsuleUI/CreateMachineSheet.swift`; wire `MachineSheet.create` in `MachineListView` to present it.

**Structure (mirror `CreateNetworkSheet` shape — Form + DisclosureGroup + command preview + Cancel/Create):**
- `@State private var draft = MachineDraft()`, `@State private var busy = false`, `@State private var useCustomImage = false`, `@State private var presetSelection = MachineImagePreset.all[0].reference`.
- **Image section:** a `Picker` over `MachineImagePreset.all` (+ a "Custom…" option) bound so that selecting a preset sets `draft.image = reference`; when Custom, show a `TextField("Image reference", text: $draft.image, prompt: Text("e.g. ubuntu:24.04"))`.
- **Resources section:** `TextField("CPUs (optional)", $draft.cpus)` (numeric prompt "e.g. 4"); `TextField("Memory (optional)", $draft.memory)` (prompt "e.g. 8G"); `Picker("Home mount", $draft.homeMount)` segmented over rw/ro/none. Inline validation captions from `actions.createProblem`-style per-field checks (call `MachineValidation.cpusProblem`/`memoryProblem` via small `actions` accessors OR show `actions.createProblem(draft)` as a single footer).
- **Options (DisclosureGroup "Advanced"):** `TextField("Name (optional)")`; `Toggle("Set as default", $draft.setDefault)`; `Toggle("Create without booting", $draft.noBoot)`; `TextField("Arch")` (prompt arm64), `TextField("OS")` (prompt linux), `TextField("Platform")`.
- **Explanatory copy (always visible, `.caption .secondary`):** first-boot provisioning — "The first boot downloads the image and provisions a persistent Linux environment. This can take several minutes." persistent-home — a line that reflects the chosen `home-mount` ("Your home directory will be mounted **\(draft.homeMount)**. Files inside the machine persist across stops; deleting the machine erases them.").
- **Command preview:** `Text(actions.commandPreview(for: draft))` monospaced in a rounded surface.
- **Buttons:** Cancel; Create (disabled `!actions.canCreate(draft) || busy`) → `busy = true; Task { let ok = await actions.create(draft: draft); busy = false; if ok { onClose() } }`. Because create registers a `TaskCenter` task, the sheet closes immediately on success and progress shows in Activity.

- [ ] **Step 1:** Implement the sheet. **Step 2:** In `MachineListView`, present it for `.create`. **Step 3: Verify** — `make build && make app && make run`; open Create, confirm preview updates live, presets populate the image, validation gates the button. (Do NOT actually create a real machine here — that's Phase H.) **Commit** — `feat(ui): machine create wizard with first-boot + persistent-home explanation`.

---

## Phase F — Settings form, set-default banner, stop & delete banners

### Task F1: `MachineSettingsSheet` (set form)

**Files:** Create `Sources/CapsuleUI/MachineSettingsSheet.swift`; present from `MachineSheet.settings(name)`.

**Structure:** `init(actions:, machine: Machine, onClose:)`; `@State var draft: MachineSettingsDraft` seeded `MachineSettingsDraft(machine: machine)`. Form with CPUs / Memory / Home-mount (segmented). A prominent note: "Changes take effect after the machine restarts." Command preview = `actions.settingsPreview(name: machine.name, draft: draft)`. Buttons: Cancel; Save (disabled when `actions.settingsProblem(draft) != nil`) → `Task { if await actions.apply(settings: draft, to: machine.name) { onClose() } }`. On success the inspector shows the persistent restart banner (already implemented D2).

- [ ] **Step 1:** Implement. **Step 2:** Present from `MachineListView`. **Step 3: Verify** — `make build && make app && make run`; open Settings, Save, confirm the restart-required banner appears on the inspector. **Commit** — `feat(ui): machine settings form (set) with restart-required follow-through`.

---

### Task F2: Banner host — set-default Undo, stop reopen/restart, created, implicit-boot

**Files:** Create `Sources/CapsuleUI/MachineBannerView.swift`; host it in `MachineListView` (e.g. a top overlay/safeAreaInset bound to `actions.banner`).

**Rendering by `MachineBanner.Kind`:**
- `.created(name)` → info banner, message, Dismiss.
- `.implicitBoot(name)` → info banner "Capsule is booting \(name) to open the shell." Dismiss.
- `.stopped(name)` → "Machine \(name) stopped." buttons **Open Shell** (`actions.openShell(name:)`) and **Restart** (`Task { await actions.restartNow(name) }`), Dismiss.
- `.madeDefault(name, previous)` → "\(name) is now the default." button **Undo** (`Task { await actions.revertDefault() }`) shown only when `previous != nil`, Dismiss.
- Dismiss sets `actions.banner = nil`.

> `actions.banner` must be settable from the view → it's already `public var banner: MachineBanner?`. Use `@Bindable var actions` or pass a closure; simplest is `@Bindable`.

- [ ] **Step 1:** Implement `MachineBannerView(actions:)`. **Step 2:** Host in `MachineListView` (`.safeAreaInset(edge: .top)` when `actions.banner != nil`). Make `actions` `@Bindable` in `MachineListView`. **Step 3: Verify** — `make build && make app && make run`; trigger Make Default → Undo, Stop → Open Shell/Restart. **Commit** — `feat(ui): machine action banners (undo default, reopen/restart, implicit boot)`.

---

### Task F3: Delete confirmation wiring

**Files:** Modify `MachineListView.swift` (ensure `.confirm` presents `ConfirmationSheet` and `performConfirmed` routes `.deleteMachine` → `actions.delete`).

> Likely already wired in D1; this task verifies + adds a test-less GUI check and a context-menu/toolbar `Delete…` for the current selection. Confirm the `ConfirmationSheet` shows the persistent-storage warning from B8.

- [ ] **Step 1:** Ensure single + (optional) multi delete route through `ConfirmationRequest.deleteMachine`. For multi-select, present a confirm per the first or a combined message (keep single-name for v1; if multiple selected, iterate `delete` after one combined confirm — reuse `deleteMachine(name:)` per name or add a simple multi message). Keep it simple: support single-selection delete; disable Delete when `selection.count != 1` if multi isn't needed. **Step 2: Verify** — `make build && make app && make run`; Delete shows the explicit warning and removes the row. **Commit** — `feat(ui): machine delete confirmation flow`.

---

## Phase G — Shell, logs, menu

### Task G1: `MachineLogsView` — Boot vs Session sub-tabs

**Files:** Create `Sources/CapsuleUI/MachineLogsView.swift`; present from `MachineSheet.logs(name)`.

**Structure:** `init(name: String, bootLogs: LogsModel, sessionLogs: LogsModel, onClose:)` — but construction of two `LogsModel(source: .machine(backend))` needs Backend, which UI can't import. **Resolution:** build the two models in the composition root and inject a factory, OR expose a domain-level factory on `MachineActionsModel`/a new `MachineLogsModels` holder. Cleanest: add to `MachineActionsModel` (which already holds `backend`) a method `func makeLogsModels() -> (boot: LogsModel, session: LogsModel)` returning `LogsModel(source: .machine(backend))` with `.boot` preset (boot=true/false). Then `MachineLogsView(name:, models: actions.makeLogsModels())`.
- Two `LogsModel`: `boot.boot = true`, `session.boot = false`; both `follow = false` initially (snapshot) with a Follow toggle.
- A `Picker`/segmented control "Boot log" / "Session log" switching which model feeds `LogsPaneView`.
- Reuse `LogsPaneView(model:onOpenInWindow:nil)`.
- `.task { bootModels.start(id: name); sessionModels.start(id: name) }` (start both so buffers populate); or start lazily on tab switch.

> Add `makeLogsModels()` to `MachineActionsModel` in this task (it has `backend`). It returns models seeded with `.machine` source. Add a focused domain test that the two models have `boot` set oppositely.

- [ ] **Step 1: Failing test** (domain factory):

```swift
//  in MachineActionsModelShellTests.swift or a new file
@MainActor func test_makeLogsModels_bootSplit() {
    let a = MachineActionsModel(backend: MockBackend(machines: []), reloadList: {})
    let pair = a.makeLogsModels()
    XCTAssertTrue(pair.boot.boot)
    XCTAssertFalse(pair.session.boot)
}
```

- [ ] **Step 2: FAIL.** **Step 3:** add `makeLogsModels()` to `MachineActionsModel`; implement `MachineLogsView` and present it from `MachineListView` `.logs`. **Step 4:** `make test` PASS + `make build && make app && make run` (open View Logs, toggle Boot/Session). **Step 5: Commit** — `feat(ui): machine logs view splitting boot vs session`.

---

### Task G2: Machine main-menu + toolbar shell action

**Files:** Modify `Sources/CapsuleApp/CapsuleCommands.swift` (add a `CommandMenu("Machine")`); ensure `MachineListView` toolbar has an `Open Shell` button for the current selection.

**Menu items (gated on a single selection + capability):** Open Shell, View Logs, Inspect, Settings…, Make Default, Stop, Delete…, Create Machine… Each routes to the same actions/sheets the context menu uses. Since menus live in `CapsuleApp` and need selection/state, follow the existing `CapsuleCommands` pattern (it likely reads `ShellState`/focused values). If wiring selection into the menu is heavy, scope this task to: **Create Machine…** (always available when machines supported) + **Open Machine Shell** (default machine) as menu commands, plus a toolbar **Open Shell** in `MachineListView`. Keep parity with the "menu + toolbar now" decision; the command palette remains M11.

- [ ] **Step 1:** Add the `Machine` command menu (mirror how an existing `CommandMenu`/`CommandGroup` is built in `CapsuleCommands.swift`). Wire at least Create + Open Default Shell through `ShellState`/environment. **Step 2:** Add a toolbar `Open Shell` button to `MachineListView` enabled when `selection.count == 1`. **Step 3: Verify** — `make build && make app && make run`; menu items work. **Commit** — `feat(app): Machine menu + toolbar shell action`.

---

## Phase H — Live wire-shape lock, integration, review

### Task H1: Live wire-shape probe (lock fixtures)

**Files:** Possibly modify `WireModels.swift` / `OutputParser.swift` (trim aliases to the real shape); update `OutputParserMachineTests.swift` fixtures to the captured JSON.

- [ ] **Step 1:** With the system service running, create a real machine and capture shapes:
  ```bash
  container machine create alpine:3.22 --name capsule-probe --no-boot
  container machine list --format json
  container machine inspect capsule-probe
  ```
  (If `--no-boot` still provisions slowly, allow a few minutes. If create must boot, drop `--no-boot`.)
- [ ] **Step 2:** Compare the real JSON keys against `CLIMachineRecord`'s `CodingKeys`. Trim the aliases to the actual spellings; fix `parseMachines`/`parseMachine` field mapping (esp. `default`/`isDefault`, `ipAddress`, `created*`, `cpus` numeric vs string, `memory`/`disk` strings). Update the parser fixtures to the captured JSON (keep the lossy/drop-unnamed test).
- [ ] **Step 3:** `make test` PASS with real-shape fixtures.
- [ ] **Step 4: Tear down** the probe machine: `container machine delete capsule-probe` and confirm `container machine list` no longer lists it.
- [ ] **Step 5: Commit** — `fix(backend): lock machine wire shape to real container CLI output`.

---

### Task H2: Live integration test (gated)

**Files:** Create `Tests/CapsuleIntegrationTests/MachineIntegrationTests.swift` (match the existing integration-test target/dir + the `CAPSULE_INTEGRATION=1` gate pattern used by M8's volume/network/DNS integration tests).

- [ ] **Step 1:** Write a gated test that, only when `CAPSULE_INTEGRATION=1`, drives `CLIContainerBackend`: create `capsule-it-<fixed-suffix>` (no `Date.now`; use a constant suffix) → list (assert present) → inspect (assert decodes) → `setMachine(cpus:)` → `setDefaultMachine` → `fetchMachineLogs(boot:true)` → `stopMachine` → `deleteMachine` → list (assert absent). Use `defer`/teardown to delete even on failure. Mirror the structure/gating of the existing M8 integration tests exactly (find them: `grep -rn CAPSULE_INTEGRATION Tests`).
- [ ] **Step 2: Run** — `CAPSULE_INTEGRATION=1 make test` (or the project's documented integration invocation). Confirm the full lifecycle passes against the real CLI and leaves no machine behind.
- [ ] **Step 3: Commit** — `test(integration): machine lifecycle against real container CLI`.

---

### Task H3: Full suite + whole-branch review

- [ ] **Step 1:** `make ci` (build + format + lint + arch + all unit tests) — all green.
- [ ] **Step 2:** `make app` — the `.app` builds, links, and signs.
- [ ] **Step 3:** Interactive GUI smoke: `make run`, then exercise every acceptance item (list+default badge, create wizard incl. first-boot copy, implicit-boot indication on shell of a stopped machine, restart-required banner after set, set-default + Undo, boot/session log split, stop reopen/restart banner, delete confirmation).
- [ ] **Step 4:** Whole-branch adversarial review (use `superpowers:requesting-code-review` or `/code-review`): focus on arch-guard compliance, error-model routing, the wire-shape decoder, and the restart/implicit-boot/default-revert state machines. Fix any Critical/High findings and re-verify.
- [ ] **Step 5: Commit** any review fixes; the branch is ready for PR/merge.

---

## Self-Review (run before execution)

**Spec coverage:** list+default badge (D1) ✓ · create wizard + first-boot/persistent-home (E1) ✓ · run/shell + implicit-boot (B14, F2, G2) ✓ · inspect summary+raw (D2) ✓ · set + restart-required banner (A3,B11,F1,D2) ✓ · set-default + revert (B12,F2) ✓ · logs boot vs session (A6,B15,G1) ✓ · stop reopen/restart banner (B13,F2) ✓ · delete explicit confirmation (B8,F3) ✓ · capability/version + Apple-silicon gating (existing `.machines` gate; C1 routes only the supported case) ✓ · normalized error model + terminal fallback (every actions method via `normalize`/`LifecycleNotice`; shell via `launchTerminal`→`copyCommand`) ✓ · tested against MockBackend (A5,B*,) ✓ · nested-virt/kernel inspector-only (A1,D2) ✓ · command palette deferred (G2 menu/toolbar instead) ✓.

**Placeholder scan:** the only intentional "fill later" is the wire-shape (A6 best-guess → H1 lock) and temporary sheet placeholders in D1 replaced by E1/F1/G1 — both are sequenced, not open-ended.

**Type consistency:** `MachineSummary`/`MachineConfiguration`/`MachineSettings` (Backend) ↔ `Machine`/`MachineState`/drafts/models (Domain) ↔ views (UI) names match across tasks; `LogSource.follow/fetch` signatures match `LogsModel.start(id:)` usage; `actions.banner`/`pendingRestart`/`currentState` referenced consistently by F2/D2.
