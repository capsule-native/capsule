# Milestone 10 · System surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the System surface over `container system` — a storage dashboard (`df`) with cleanup links, a service-logs pane (`logs`) with an empty-is-not-failure warning, an About/Diagnostics pane (`version`) for bug reports, a kernel manager (`kernel set`) in Advanced Settings, and a read-only TOML property viewer/editor/exporter with a requires-restart banner.

**Architecture:** Mirror the established vertical-slice path across the strict layers (UI → Domain → Backend port → CLI adapter → MockBackend), enforced by `ArchitectureGuardTests` (UI imports no Backend module; Domain uses no `Process`). Read surfaces become tabs inside the existing always-available `.system` detail; kernel + configuration become a new **Advanced** tab in the Settings scene. Reuse `LogsModel`/`LogSource`, `TaskCenter` streaming, the existing prune actions, `DiagnosticBundle`, and the M9 restart-banner pattern.

**Tech Stack:** Swift 6 / SwiftUI, SwiftPM package of modules + XcodeGen app target. Build/test via `make` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the `Makefile` exports this). No new third-party dependency (TOML validation is a scoped in-house linter).

## Global Constraints

- **Layering (hard rule, guarded):** UI (`CapsuleUI`) imports no Backend module (`CapsuleBackend`/`CapsuleCLIBackend`/`CapsuleTerminal`); Domain (`CapsuleDomain`) imports no UI and never uses `Foundation.Process`. Avoid the literal substrings `import CapsuleBackend`/`import CapsuleCLIBackend`/`import CapsuleTerminal`/`import CapsuleUI` inside *comments* in UI files — `ArchitectureGuardTests` uses a naive `source.contains(...)` scan (M9 gotcha #2).
- **Run full `make test`, not just `make build`, after any task that adds a domain test or touches the arch guard** (M9 lesson — the arch guard only runs under XCTest).
- **CLI wire shapes are fixed to `container` v1.0.0** as captured 2026-06-30 (see each task's fixture). Decode leniently via `OutputParser.lossyList`.
- **`container system property` is READ-ONLY** (no `set`/`get`). The TOML surface is viewer/editor/**exporter** only; never write the live config. Model requires-restart as explicit UI state.
- **Kernel set writes user-owned files → no sudo.** Do NOT add a privileged handoff for it. (Contingency only: if the live probe shows it needs sudo, reuse the DNS `runPrivilegedInTerminal` pattern — not expected.)
- **Never present empty as failure** in the service-logs pane.
- **Every backend call routes through `ErrorNormalizer.normalize → CapsuleError`** at the domain boundary (the `normalize` closure injected into each model).
- **Commit after each task** with a conventional-commit message; end commit messages with the two trailers used on this branch (`Co-Authored-By: Claude Opus 4.8 …` / `Claude-Session: …`).
- **License header:** every new `.swift` file starts with the standard 5-line header (`//  <Name>.swift` / `//  Capsule` / `//` / `//  Copyright © 2026 Capsule. All rights reserved.` / `//`) — the pre-commit hook enforces it.

---

## Ground truth (probed live 2026-06-30, `container` v1.0.0)

```
# system df --format json
{ "containers": {"active":0,"reclaimable":454991872,"sizeInBytes":454991872,"total":1},
  "images":     {"active":1,"reclaimable":974934016,"sizeInBytes":1302421504,"total":4},
  "volumes":    {"active":0,"reclaimable":0,"sizeInBytes":0,"total":0} }
# active/total are COUNTS; reclaimable/sizeInBytes are BYTES. inUse = sizeInBytes - reclaimable.

# system version --format json   (ARRAY)
[{"appName":"container","buildType":"release","commit":"ee848e3…","version":"1.0.0"},
 {"appName":"container-apiserver","buildType":"release","commit":"ee848e3…",
  "version":"container-apiserver version 1.0.0 (build: release, commit: ee848e3)"}]

# system property list --format json   (nested, mixed scalar types)
{"build":{"cpus":2,"image":"ghcr.io/…","memory":"2048mb","rosetta":true},
 "container":{"cpus":4,"memory":"1gb"},"dns":{},"kernel":{"binaryPath":"opt/…","url":"https://…"},
 "machine":{"cpus":5,"homeMount":"rw","memory":"16gb"},"network":{},
 "registry":{"domain":"docker.io"},"vminit":{"image":"ghcr.io/…"}}
# Default --format is toml (used verbatim for the editor buffer + export).

# system logs [--follow] [--last <number>[m|h|d]]   (default 5m; text; no id, no --boot)
# system kernel set [--arch arm64|amd64] [--binary <path>] [--tar <path|URL>] [--recommended] [--force]
```

---

# Phase 1 — Backend foundation (port → adapter → mock → parsers)

Each task here is a vertical slice for one capability: value type(s) + wire record + parser + `CLICommand` + port method + `CLIContainerBackend` + `MockBackend`, with a parser fixture test and an adapter (Stub) argv+decode test. Adding a protocol requirement breaks `MockBackend`/`CLIContainerBackend` compilation until both are updated, so each task updates all three together to keep the build green.

### Task 1: Storage usage (`system df`)

**Files:**
- Modify: `Sources/CapsuleBackend/BackendResourceTypes.swift` (append `StorageUsage`, `CategoryUsage`)
- Modify: `Sources/CapsuleCLIBackend/WireModels.swift` (append `CLIDiskUsageRecord`)
- Modify: `Sources/CapsuleCLIBackend/OutputParser.swift` (append `parseDiskUsage`)
- Modify: `Sources/CapsuleCLIBackend/CLICommand.swift` (append `systemDiskUsage()`)
- Modify: `Sources/CapsuleBackend/ContainerBackend.swift` (declare `systemDiskUsage()`)
- Modify: `Sources/CapsuleCLIBackend/CLIContainerBackend.swift` (implement)
- Modify: `Sources/CapsuleBackend/MockBackend.swift` (implement + sample state)
- Create: `Tests/CapsuleUnitTests/Fixtures/system-df.json`
- Test: `Tests/CapsuleUnitTests/OutputParserTests.swift`, `Tests/CapsuleUnitTests/CLIContainerBackendTests.swift`

**Interfaces:**
- Produces: `StorageUsage { images, containers, volumes: CategoryUsage }`; `CategoryUsage { total: Int; active: Int; sizeInBytes: Int; reclaimable: Int; var inUseBytes: Int { sizeInBytes - reclaimable } }`; `OutputParser.parseDiskUsage(_ data: Data) throws -> StorageUsage`; `CLICommand.systemDiskUsage() -> [String]`; `ContainerBackend.systemDiskUsage() async throws -> StorageUsage`.

- [ ] **Step 1: Write the fixture**

Create `Tests/CapsuleUnitTests/Fixtures/system-df.json` with the captured object above (exact bytes from Ground truth).

- [ ] **Step 2: Write the failing parser + value-type test**

In `OutputParserTests.swift`:
```swift
func testParseDiskUsageSplitsCountsFromBytes() throws {
    let usage = try OutputParser.parseDiskUsage(Fixture.data("system-df"))
    XCTAssertEqual(usage.images.total, 4)
    XCTAssertEqual(usage.images.active, 1)
    XCTAssertEqual(usage.images.sizeInBytes, 1_302_421_504)
    XCTAssertEqual(usage.images.reclaimable, 974_934_016)
    XCTAssertEqual(usage.images.inUseBytes, 1_302_421_504 - 974_934_016)
    XCTAssertEqual(usage.containers.total, 1)
    XCTAssertEqual(usage.volumes.sizeInBytes, 0)
}
```

- [ ] **Step 3: Run it — expect FAIL** (`parseDiskUsage`/`StorageUsage` undefined). Run: `make test` (or scope to the test). Expected: compile error / fail.

- [ ] **Step 4: Add the value types**

Append to `BackendResourceTypes.swift`:
```swift
/// A backend's view of disk usage for one resource category (`system df`).
/// `total`/`active` are item COUNTS; `sizeInBytes`/`reclaimable` are BYTES.
public struct CategoryUsage: Sendable, Equatable, Codable {
    public var total: Int
    public var active: Int
    public var sizeInBytes: Int
    public var reclaimable: Int
    public var inUseBytes: Int { max(0, sizeInBytes - reclaimable) }

    public init(total: Int, active: Int, sizeInBytes: Int, reclaimable: Int) {
        self.total = total
        self.active = active
        self.sizeInBytes = sizeInBytes
        self.reclaimable = reclaimable
    }
}

/// Disk usage across images, containers, and volumes (`container system df`).
public struct StorageUsage: Sendable, Equatable, Codable {
    public var images: CategoryUsage
    public var containers: CategoryUsage
    public var volumes: CategoryUsage

    public init(images: CategoryUsage, containers: CategoryUsage, volumes: CategoryUsage) {
        self.images = images
        self.containers = containers
        self.volumes = volumes
    }
}
```

- [ ] **Step 5: Add the wire record + parser**

Append to `WireModels.swift`:
```swift
// MARK: - System df

/// `container system df --format json` shape. Each category mixes item counts
/// (`total`/`active`) with byte totals (`reclaimable`/`sizeInBytes`).
struct CLIDiskUsageRecord: Decodable {
    let images: Category
    let containers: Category
    let volumes: Category

    struct Category: Decodable {
        let total: Int
        let active: Int
        let reclaimable: Int
        let sizeInBytes: Int
    }
}
```
Append to `OutputParser.swift` (new `// MARK: - System df` section):
```swift
public static func parseDiskUsage(_ data: Data) throws -> StorageUsage {
    let record: CLIDiskUsageRecord
    do {
        record = try decoder.decode(CLIDiskUsageRecord.self, from: data)
    } catch {
        throw BackendError.decodingFailed(String(describing: error))
    }
    func map(_ c: CLIDiskUsageRecord.Category) -> CategoryUsage {
        CategoryUsage(
            total: c.total, active: c.active,
            sizeInBytes: c.sizeInBytes, reclaimable: c.reclaimable)
    }
    return StorageUsage(
        images: map(record.images),
        containers: map(record.containers),
        volumes: map(record.volumes))
}
```

- [ ] **Step 6: Run the parser test — expect PASS.** Run: `make test`.

- [ ] **Step 7: Add the `CLICommand` + adapter argv test**

Append to `CLICommand.swift` (System section):
```swift
public static func systemDiskUsage() -> [String] {
    ArgumentBuilder("system", "df").flag("--format", "json").arguments
}
```
In `CLIContainerBackendTests.swift`:
```swift
func testSystemDiskUsageArgvAndDecode() async throws {
    let stub = StubProcessRunner()
    stub.result = CommandResult(
        exitCode: 0, stdout: String(decoding: Fixture.data("system-df"), as: UTF8.self), stderr: "")
    let backend = CLIContainerBackend(executableURL: URL(fileURLWithPath: "/usr/bin/container"), runner: stub)
    let usage = try await backend.systemDiskUsage()
    XCTAssertEqual(stub.lastCall, ["system", "df", "--format", "json"])
    XCTAssertEqual(usage.images.total, 4)
}
```

- [ ] **Step 8: Declare the port method + implement adapter + mock**

In `ContainerBackend.swift` (System section), declare:
```swift
/// Disk usage for images, containers, and volumes (`system df`).
func systemDiskUsage() async throws -> StorageUsage
```
In `CLIContainerBackend.swift` (System section), implement:
```swift
public func systemDiskUsage() async throws -> StorageUsage {
    let output = try await runChecked(CLICommand.systemDiskUsage())
    return try OutputParser.parseDiskUsage(Data(output.stdout.utf8))
}
```
In `MockBackend.swift`, add stored sample + method:
```swift
public var diskUsage = StorageUsage(
    images: CategoryUsage(total: 4, active: 1, sizeInBytes: 1_302_421_504, reclaimable: 974_934_016),
    containers: CategoryUsage(total: 1, active: 0, sizeInBytes: 454_991_872, reclaimable: 454_991_872),
    volumes: CategoryUsage(total: 0, active: 0, sizeInBytes: 0, reclaimable: 0))

public func systemDiskUsage() async throws -> StorageUsage { diskUsage }
```
(If `MockBackend` is configured to throw via an existing error-injection switch, follow that file's established pattern; otherwise return the sample.)

- [ ] **Step 9: Run — expect PASS.** Run: `make test`. Expected: both new tests pass; suite green.

- [ ] **Step 10: Commit**
```bash
git add -A && git commit -m "feat(backend): system df storage usage (port+CLI+mock+parser)"
```

### Task 2: Component versions (`system version` array)

**Files:** `WireModels.swift` (extend `CLIVersionComponent`), `OutputParser.swift` (`parseComponentVersions`), `BackendResourceTypes.swift` (`ComponentVersion`), `ContainerBackend.swift`, `CLIContainerBackend.swift`, `MockBackend.swift`, `CLICommand.swift` (reuse `version()` argv via a `systemVersion()` alias), tests + reuse `Fixtures/system-version.json`.

**Interfaces:**
- Produces: `ComponentVersion { appName, version, buildType, commit: String }`; `OutputParser.parseComponentVersions(_:) throws -> [ComponentVersion]`; `ContainerBackend.systemComponentVersions() async throws -> [ComponentVersion]`. (The existing `version() -> BackendVersion` and `parseVersion` stay unchanged.)

- [ ] **Step 1: Failing parser test** in `OutputParserTests.swift`:
```swift
func testParseComponentVersionsReadsArray() throws {
    let comps = try OutputParser.parseComponentVersions(Fixture.data("system-version"))
    XCTAssertEqual(comps.count, 2)
    XCTAssertEqual(comps[0].appName, "container")
    XCTAssertEqual(comps[0].version, "1.0.0")
    XCTAssertEqual(comps[0].buildType, "release")
    XCTAssertTrue(comps[1].appName.contains("apiserver"))
}
```

- [ ] **Step 2: Run — expect FAIL.** `make test`.

- [ ] **Step 3: Extend the wire record + add value type + parser.**

`WireModels.swift` — extend `CLIVersionComponent` additively (optional new fields keep `parseVersion` working):
```swift
struct CLIVersionComponent: Decodable {
    let appName: String
    let version: String
    let buildType: String?
    let commit: String?
}
```
`BackendResourceTypes.swift`:
```swift
/// One component of `container system version` (CLI client, API server, …).
public struct ComponentVersion: Sendable, Equatable, Identifiable, Codable {
    public var id: String { appName }
    public var appName: String
    public var version: String
    public var buildType: String
    public var commit: String

    public init(appName: String, version: String, buildType: String, commit: String) {
        self.appName = appName
        self.version = version
        self.buildType = buildType
        self.commit = commit
    }
}
```
`OutputParser.swift` (System version section):
```swift
public static func parseComponentVersions(_ data: Data) throws -> [ComponentVersion] {
    try lossyList(data, decode: CLIVersionComponent.self).map {
        ComponentVersion(
            appName: $0.appName, version: $0.version,
            buildType: $0.buildType ?? "", commit: $0.commit ?? "")
    }
}
```

- [ ] **Step 4: Run — expect PASS.** `make test`.

- [ ] **Step 5: Add the port method + adapter + mock + argv test.**

`CLICommand.swift`:
```swift
public static func systemVersion() -> [String] { version() }  // same argv; named for clarity
```
`ContainerBackend.swift`: `func systemComponentVersions() async throws -> [ComponentVersion]`
`CLIContainerBackend.swift`:
```swift
public func systemComponentVersions() async throws -> [ComponentVersion] {
    let output = try await runChecked(CLICommand.systemVersion())
    return try OutputParser.parseComponentVersions(Data(output.stdout.utf8))
}
```
`MockBackend.swift`:
```swift
public var componentVersions: [ComponentVersion] = [
    ComponentVersion(appName: "container", version: "1.0.0", buildType: "release", commit: "ee848e3"),
    ComponentVersion(appName: "container-apiserver",
        version: "container-apiserver version 1.0.0 (build: release, commit: ee848e3)",
        buildType: "release", commit: "ee848e3")]
public func systemComponentVersions() async throws -> [ComponentVersion] { componentVersions }
```
Adapter test in `CLIContainerBackendTests.swift` asserting `stub.lastCall == ["system","version","--format","json"]` and `comps.count == 2`.

- [ ] **Step 6: Run — expect PASS.** `make test`.
- [ ] **Step 7: Commit** `feat(backend): system version component list`.

### Task 3: Properties (`system property list` — JSON + TOML)

**Files:** `BackendResourceTypes.swift` (`SystemProperties`, `PropertySection`), `WireModels.swift` (`CLIPropertiesRecord` + a `JSONScalar` enum), `OutputParser.swift` (`parseProperties`), `CLICommand.swift` (`systemPropertiesJSON()`, `systemPropertiesTOML()`), port + adapter + mock, `Fixtures/property-list.json`, tests.

**Interfaces:**
- Produces: `PropertySection { name: String; entries: [PropertyEntry] }`, `PropertyEntry { key: String; value: String }`, `SystemProperties { sections: [PropertySection] }` (both sorted alphabetically for stable display); `OutputParser.parseProperties(_:) throws -> SystemProperties`; `ContainerBackend.systemProperties() async throws -> SystemProperties` and `systemPropertiesTOML() async throws -> String`.

- [ ] **Step 1: Fixture** `Tests/CapsuleUnitTests/Fixtures/property-list.json` = the captured JSON object (Ground truth).

- [ ] **Step 2: Failing parser test:**
```swift
func testParsePropertiesFlattensSectionsSorted() throws {
    let props = try OutputParser.parseProperties(Fixture.data("property-list"))
    XCTAssertEqual(props.sections.map(\.name),
        ["build","container","dns","kernel","machine","network","registry","vminit"])
    let kernel = props.sections.first { $0.name == "kernel" }!
    XCTAssertEqual(kernel.entries.map(\.key), ["binaryPath","url"])
    let build = props.sections.first { $0.name == "build" }!
    XCTAssertEqual(build.entries.first { $0.key == "rosetta" }?.value, "true")
    XCTAssertEqual(build.entries.first { $0.key == "cpus" }?.value, "2")
}
```

- [ ] **Step 3: Run — expect FAIL.** `make test`.

- [ ] **Step 4: Value types + wire record + parser.**

`BackendResourceTypes.swift`:
```swift
/// One key/value within a property section, rendered to a display string.
public struct PropertyEntry: Sendable, Equatable, Codable {
    public var key: String
    public var value: String
    public init(key: String, value: String) { self.key = key; self.value = value }
}

/// A `[section]` of merged system properties.
public struct PropertySection: Sendable, Equatable, Identifiable, Codable {
    public var id: String { name }
    public var name: String
    public var entries: [PropertyEntry]
    public init(name: String, entries: [PropertyEntry]) { self.name = name; self.entries = entries }
}

/// Merged system properties (`container system property list`), read-only.
public struct SystemProperties: Sendable, Equatable, Codable {
    public var sections: [PropertySection]
    public init(sections: [PropertySection]) { self.sections = sections }
    public func section(_ name: String) -> PropertySection? { sections.first { $0.name == name } }
}
```
`WireModels.swift` — a scalar enum that renders mixed JSON values to strings, plus the nested decode:
```swift
// MARK: - System properties

/// A TOML/JSON scalar (Int, Double, Bool, or String) rendered to a display string.
enum JSONScalar: Decodable {
    case string(String), int(Int), double(Double), bool(Bool)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        self = .string(try c.decode(String.self))
    }
    var display: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        }
    }
}
```
`OutputParser.swift`:
```swift
public static func parseProperties(_ data: Data) throws -> SystemProperties {
    let raw: [String: [String: JSONScalar]]
    do {
        raw = try decoder.decode([String: [String: JSONScalar]].self, from: data)
    } catch {
        throw BackendError.decodingFailed(String(describing: error))
    }
    let sections = raw.keys.sorted().map { name in
        let entries = (raw[name] ?? [:]).keys.sorted().map { key in
            PropertyEntry(key: key, value: raw[name]![key]!.display)
        }
        return PropertySection(name: name, entries: entries)
    }
    return SystemProperties(sections: sections)
}
```

- [ ] **Step 5: Run — expect PASS.** `make test`.

- [ ] **Step 6: Commands + port + adapter + mock + argv test.**

`CLICommand.swift`:
```swift
public static func systemPropertiesJSON() -> [String] {
    ArgumentBuilder("system", "property", "list").flag("--format", "json").arguments
}
public static func systemPropertiesTOML() -> [String] {
    ArgumentBuilder("system", "property", "list").arguments  // default format is toml
}
```
`ContainerBackend.swift`:
```swift
func systemProperties() async throws -> SystemProperties
func systemPropertiesTOML() async throws -> String
```
`CLIContainerBackend.swift`:
```swift
public func systemProperties() async throws -> SystemProperties {
    let output = try await runChecked(CLICommand.systemPropertiesJSON())
    return try OutputParser.parseProperties(Data(output.stdout.utf8))
}
public func systemPropertiesTOML() async throws -> String {
    try await runChecked(CLICommand.systemPropertiesTOML()).stdout
}
```
`MockBackend.swift` — a canned TOML string + structured sample:
```swift
public var propertiesTOML = """
[build]
cpus = 2
memory = "2048mb"
rosetta = true

[kernel]
binaryPath = "opt/kata/share/kata-containers/vmlinux-6.18.15-186"
url = "https://github.com/kata-containers/kata-containers/releases/download/3.28.0/kata-static-3.28.0-arm64.tar.zst"

[machine]
cpus = 5
homeMount = "rw"
memory = "16gb"
"""
public var properties = SystemProperties(sections: [
    PropertySection(name: "build", entries: [
        .init(key: "cpus", value: "2"), .init(key: "memory", value: "2048mb"),
        .init(key: "rosetta", value: "true")]),
    PropertySection(name: "kernel", entries: [
        .init(key: "binaryPath", value: "opt/kata/share/kata-containers/vmlinux-6.18.15-186"),
        .init(key: "url", value: "https://github.com/kata-containers/…/kata-static-3.28.0-arm64.tar.zst")]),
])
public func systemProperties() async throws -> SystemProperties { properties }
public func systemPropertiesTOML() async throws -> String { propertiesTOML }
```
Adapter argv tests: `["system","property","list","--format","json"]` and `["system","property","list"]`.

- [ ] **Step 7: Run — expect PASS.** `make test`.
- [ ] **Step 8: Commit** `feat(backend): system property list (json + toml)`.

### Task 4: Service logs (`system logs`)

**Files:** `CLICommand.swift` (`systemLogs(last:)`, `systemLogsFollow()`), `ContainerBackend.swift` + `CLIContainerBackend.swift` + `MockBackend.swift`, tests.

**Interfaces:**
- Produces: `CLICommand.systemLogs(last: String) -> [String]`, `CLICommand.systemLogsFollow() -> [String]`; `ContainerBackend.fetchSystemLogs(last: String) async throws -> [OutputLine]`, `ContainerBackend.followSystemLogs() -> AsyncThrowingStream<OutputLine, Error>`.

- [ ] **Step 1: Failing adapter test** in `CLIContainerBackendTests.swift`:
```swift
func testSystemLogsArgvAndSplit() async throws {
    let stub = StubProcessRunner()
    stub.result = CommandResult(exitCode: 0, stdout: "line one\nline two\n", stderr: "")
    let backend = CLIContainerBackend(executableURL: URL(fileURLWithPath: "/usr/bin/container"), runner: stub)
    let lines = try await backend.fetchSystemLogs(last: "1h")
    XCTAssertEqual(stub.lastCall, ["system", "logs", "--last", "1h"])
    XCTAssertEqual(lines.map(\.text), ["line one", "line two"])
}
func testFetchSystemLogsEmptyIsEmptyNotBlankLine() async throws {
    let stub = StubProcessRunner()
    stub.result = CommandResult(exitCode: 0, stdout: "", stderr: "")
    let backend = CLIContainerBackend(executableURL: URL(fileURLWithPath: "/usr/bin/container"), runner: stub)
    let lines = try await backend.fetchSystemLogs(last: "5m")
    XCTAssertTrue(lines.isEmpty)
}
```

- [ ] **Step 2: Run — expect FAIL.** `make test`.

- [ ] **Step 3: Commands + port + adapter + mock.**

`CLICommand.swift`:
```swift
public static func systemLogs(last: String) -> [String] {
    ArgumentBuilder("system", "logs").flag("--last", last).arguments
}
public static func systemLogsFollow() -> [String] {
    ArgumentBuilder("system", "logs").option("--follow", enabled: true).arguments
}
```
`ContainerBackend.swift`:
```swift
/// Fetches a snapshot of the system service logs over the last `last` window (e.g. "5m","1h","1d").
func fetchSystemLogs(last: String) async throws -> [OutputLine]
/// Follows the system service logs as a live stream.
func followSystemLogs() -> AsyncThrowingStream<OutputLine, Error>
```
`CLIContainerBackend.swift` (mirror `fetchLogs`'s trailing-newline trimming):
```swift
public func fetchSystemLogs(last: String) async throws -> [OutputLine] {
    let output = try await runChecked(CLICommand.systemLogs(last: last))
    let text = output.stdout.hasSuffix("\n") ? String(output.stdout.dropLast()) : output.stdout
    guard !text.isEmpty else { return [] }
    return text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { OutputLine(source: .stdout, text: String($0)) }
}
public func followSystemLogs() -> AsyncThrowingStream<OutputLine, Error> {
    streamRaw(CLICommand.systemLogsFollow())
}
```
`MockBackend.swift`:
```swift
public var systemLogLines: [OutputLine] = [
    OutputLine(source: .stdout, text: "apiserver: started"),
    OutputLine(source: .stdout, text: "apiserver: listening")]
public func fetchSystemLogs(last: String) async throws -> [OutputLine] { systemLogLines }
public func followSystemLogs() -> AsyncThrowingStream<OutputLine, Error> {
    AsyncThrowingStream { continuation in
        for line in systemLogLines { continuation.yield(line) }
        continuation.finish()
    }
}
```

- [ ] **Step 4: Run — expect PASS.** `make test`.
- [ ] **Step 5: Commit** `feat(backend): system logs fetch + follow`.

### Task 5: Kernel set (`system kernel set`) + TaskCenter kind

**Files:** `BackendResourceTypes.swift` (`KernelConfiguration`, `KernelSource`, `KernelArch`), `CLICommand.swift` (`setKernel(_:)`), port + adapter + mock, `Sources/CapsuleDomain/TaskCenter.swift` (`OperationKind.systemKernelInstall`), tests.

**Interfaces:**
- Produces: `KernelArch { arm64, amd64 }` (raw `String` "arm64"/"amd64"); `KernelSource { recommended; localBinary(path: String); remoteTar(url: String, member: String?) }`; `KernelConfiguration { source: KernelSource; arch: KernelArch; force: Bool; var arguments: [String] }`; `ContainerBackend.setKernel(_:) -> AsyncThrowingStream<OutputLine, Error>`; `OperationKind.systemKernelInstall`.

- [ ] **Step 1: Failing argv test** in a new `Tests/CapsuleUnitTests/KernelConfigurationTests.swift`:
```swift
func testRecommendedArgvIgnoresOtherFlagsExceptForce() {
    let argv = KernelConfiguration(source: .recommended, arch: .arm64, force: false).arguments
    XCTAssertEqual(argv, ["system", "kernel", "set", "--recommended"])
}
func testLocalBinaryArgv() {
    let argv = KernelConfiguration(
        source: .localBinary(path: "/k/vmlinux"), arch: .arm64, force: true).arguments
    XCTAssertEqual(argv, ["system","kernel","set","--arch","arm64","--binary","/k/vmlinux","--force"])
}
func testRemoteTarArgvWithMember() {
    let argv = KernelConfiguration(
        source: .remoteTar(url: "https://x/k.tar", member: "boot/vmlinux"),
        arch: .amd64, force: false).arguments
    XCTAssertEqual(argv,
        ["system","kernel","set","--arch","amd64","--tar","https://x/k.tar","--binary","boot/vmlinux"])
}
```

- [ ] **Step 2: Run — expect FAIL.** `make test`.

- [ ] **Step 3: Value types (argv = single source of truth).**

`BackendResourceTypes.swift`:
```swift
/// Architecture for a kernel install.
public enum KernelArch: String, Sendable, Equatable, Codable, CaseIterable {
    case arm64, amd64
}

/// Where a kernel comes from. `recommended` downloads a known-good kernel and takes
/// precedence over all other flags (so its argv omits arch/binary/tar).
public enum KernelSource: Sendable, Equatable {
    case recommended
    case localBinary(path: String)
    case remoteTar(url: String, member: String?)
}

/// A typed `container system kernel set` invocation.
public struct KernelConfiguration: Sendable, Equatable {
    public var source: KernelSource
    public var arch: KernelArch
    public var force: Bool

    public init(source: KernelSource, arch: KernelArch = .arm64, force: Bool = false) {
        self.source = source
        self.arch = arch
        self.force = force
    }

    public var arguments: [String] {
        var b = ArgumentBuilderless(["system", "kernel", "set"])
        switch source {
        case .recommended:
            b.append("--recommended")
        case .localBinary(let path):
            b.append(contentsOf: ["--arch", arch.rawValue, "--binary", path])
        case .remoteTar(let url, let member):
            b.append(contentsOf: ["--arch", arch.rawValue, "--tar", url])
            if let member, !member.isEmpty { b.append(contentsOf: ["--binary", member]) }
        }
        if force { b.append("--force") }
        return b.tokens
    }
}
```
> NOTE: `ArgumentBuilder` lives in `CapsuleCLIBackend` (the adapter), which `CapsuleBackend` must not import. To keep `KernelConfiguration.arguments` in the port module, build the array directly with a tiny local helper, OR (preferred, matching `MachineConfiguration`) define `KernelConfiguration` in whichever module already hosts `MachineConfiguration.arguments`. **Check where `MachineConfiguration` lives and co-locate `KernelConfiguration` there**, using the same argv-building approach it uses. Replace `ArgumentBuilderless` above with that approach (likely a plain `var tokens: [String] = [...]` with `append`). The test asserts the exact argv regardless of builder.

- [ ] **Step 4: Run — expect PASS.** `make test`.

- [ ] **Step 5: Command + port + adapter + mock + OperationKind.**

`CLICommand.swift`:
```swift
public static func setKernel(_ config: KernelConfiguration) -> [String] { config.arguments }
```
`ContainerBackend.swift`:
```swift
/// Installs/sets the default kernel (`system kernel set`); streams download/install progress.
func setKernel(_ config: KernelConfiguration) -> AsyncThrowingStream<OutputLine, Error>
```
`CLIContainerBackend.swift`:
```swift
public func setKernel(_ config: KernelConfiguration) -> AsyncThrowingStream<OutputLine, Error> {
    streamRaw(CLICommand.setKernel(config))
}
```
`MockBackend.swift`:
```swift
public private(set) var lastKernelConfiguration: KernelConfiguration?
public func setKernel(_ config: KernelConfiguration) -> AsyncThrowingStream<OutputLine, Error> {
    lastKernelConfiguration = config
    return AsyncThrowingStream { continuation in
        continuation.yield(OutputLine(source: .stdout, text: "Installing kernel…"))
        continuation.yield(OutputLine(source: .stdout, text: "Done."))
        continuation.finish()
    }
}
```
`TaskCenter.swift` — add the case + both switch arms:
```swift
case systemKernelInstall
// title:
case .systemKernelInstall: return "Install Kernel"
// symbolName:
case .systemKernelInstall: return "cpu.fill"
```

- [ ] **Step 6: Add a Mock adapter test** (argv via Stub stream) in `CLIContainerBackendTests.swift`:
```swift
func testSetKernelStreamsAndArgv() async throws {
    let stub = StubProcessRunner()
    stub.streamLines = [OutputLine(source: .stdout, text: "Installing")]
    let backend = CLIContainerBackend(executableURL: URL(fileURLWithPath: "/usr/bin/container"), runner: stub)
    var got: [String] = []
    for try await line in backend.setKernel(.init(source: .recommended)) { got.append(line.text) }
    XCTAssertEqual(stub.lastCall, ["system", "kernel", "set", "--recommended"])
    XCTAssertEqual(got, ["Installing"])
}
```

- [ ] **Step 7: Run — expect PASS.** `make test`.
- [ ] **Step 8: Commit** `feat(backend): system kernel set (streaming) + OperationKind`.

---

# Phase 2 — Storage dashboard

### Task 6: `StorageDashboardModel`

**Files:**
- Create: `Sources/CapsuleDomain/StorageDashboardModel.swift`
- Test: `Tests/CapsuleUnitTests/StorageDashboardModelTests.swift`

**Interfaces:**
- Consumes: `StorageUsage`/`CategoryUsage`, `ContainerBackend.systemDiskUsage()`.
- Produces: `StorageCategory { images, containers, volumes }` (with `title`); `CleanupRecommendation { category: StorageCategory; reclaimableBytes: Int }`; `StorageDashboardModel` with `loadState: StorageLoadState`, `usage: StorageUsage?`, `recommendations: [CleanupRecommendation]`, `totalReclaimableBytes`/`totalInUseBytes`, `refresh() async`, and `reclaim(_ category:)` delegating to an injected `onReclaim: @MainActor (StorageCategory) -> Void`.

- [ ] **Step 1: Failing test** in `StorageDashboardModelTests.swift`:
```swift
@MainActor
final class StorageDashboardModelTests: XCTestCase {
    func testRefreshLoadsUsageAndRecommendsOnlyReclaimable() async {
        let backend = MockBackend()  // images & containers reclaimable > 0, volumes == 0
        let model = StorageDashboardModel(backend: backend, normalize: { _ in .placeholder })
        await model.refresh()
        guard case .loaded = model.loadState else { return XCTFail("expected loaded") }
        XCTAssertEqual(model.recommendations.map(\.category), [.images, .containers])
        XCTAssertEqual(model.totalReclaimableBytes, 974_934_016 + 454_991_872)
    }
    func testReclaimDelegatesToClosure() async {
        var reclaimed: [StorageCategory] = []
        let model = StorageDashboardModel(
            backend: MockBackend(), normalize: { _ in .placeholder },
            onReclaim: { reclaimed.append($0) })
        await model.refresh()
        model.reclaim(.images)
        XCTAssertEqual(reclaimed, [.images])
    }
}
```
> `CapsuleError.placeholder`: use whatever the other model tests use as a stub normalize result (grep `normalize: { _ in` in existing tests and copy that literal). If there is no `.placeholder`, build a `CapsuleError` the way `VolumeBrowserModelTests` does.

- [ ] **Step 2: Run — expect FAIL.** `make test`.

- [ ] **Step 3: Implement the model.**
```swift
//  StorageDashboardModel.swift … (header)
//  NOTE: This module must remain free of UI and of `Foundation.Process`.
import CapsuleBackend
import Foundation
import Observation

public enum StorageCategory: String, Sendable, CaseIterable, Identifiable {
    case images, containers, volumes
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .images: return "Images"
        case .containers: return "Containers"
        case .volumes: return "Volumes"
        }
    }
}

public struct CleanupRecommendation: Sendable, Equatable, Identifiable {
    public var category: StorageCategory
    public var reclaimableBytes: Int
    public var id: String { category.rawValue }
}

public enum StorageLoadState: Sendable, Equatable {
    case idle, loading, loaded, unavailable(ErrorDetail)
}

@MainActor
@Observable
public final class StorageDashboardModel {
    public private(set) var usage: StorageUsage?
    public private(set) var loadState: StorageLoadState = .idle

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onReclaim: @MainActor (StorageCategory) -> Void

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel.defaultNormalize,
        onReclaim: @escaping @MainActor (StorageCategory) -> Void = { _ in }
    ) {
        self.backend = backend
        self.normalize = normalize
        self.onReclaim = onReclaim
    }

    public func refresh() async {
        loadState = .loading
        do {
            let u = try await backend.systemDiskUsage()
            usage = u
            loadState = .loaded
        } catch {
            loadState = .unavailable(normalize(error).detail)
        }
    }

    private func category(_ c: StorageCategory) -> CategoryUsage? {
        switch c {
        case .images: return usage?.images
        case .containers: return usage?.containers
        case .volumes: return usage?.volumes
        }
    }

    public var recommendations: [CleanupRecommendation] {
        StorageCategory.allCases.compactMap { c in
            guard let u = category(c), u.reclaimable > 0 else { return nil }
            return CleanupRecommendation(category: c, reclaimableBytes: u.reclaimable)
        }
    }

    public var totalReclaimableBytes: Int {
        StorageCategory.allCases.reduce(0) { $0 + (category($1)?.reclaimable ?? 0) }
    }
    public var totalInUseBytes: Int {
        StorageCategory.allCases.reduce(0) { $0 + (category($1)?.inUseBytes ?? 0) }
    }

    public func reclaim(_ category: StorageCategory) { onReclaim(category) }
}
```
> Use the same `ErrorDetail`/`CapsuleError.detail` and `SystemStatusModel.defaultNormalize` types the other browser models use (confirm `StorageLoadState.unavailable(ErrorDetail)` matches `VolumeLoadState`'s associated type — copy that exact type name).

- [ ] **Step 4: Run — expect PASS.** `make test`.
- [ ] **Step 5: Commit** `feat(domain): storage dashboard model + cleanup recommendations`.

### Task 7: `StorageDashboardView`

**Files:** Create `Sources/CapsuleUI/StorageDashboardView.swift`. (No unit test — verified by build now, GUI smoke later.)

**Interfaces:** Consumes `StorageDashboardModel`, `StorageCategory`, `CategoryUsage`.

- [ ] **Step 1: Implement the view.**
```swift
//  StorageDashboardView.swift … (header)
import CapsuleDomain
import SwiftUI

struct StorageDashboardView: View {
    @Bindable var model: StorageDashboardModel

    var body: some View {
        Group {
            switch model.loadState {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable(let detail):
                ContentUnavailableView(detail.headline, systemImage: "internaldrive",
                    description: Text(detail.explanation))
            case .loaded:
                ScrollView { content }
            }
        }
        .task { await model.refresh() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(StorageCategory.allCases) { category in
                if let usage = usage(for: category) {
                    StorageCategoryCard(category: category, usage: usage) {
                        model.reclaim(category)
                    }
                }
            }
            LabeledContent("Total reclaimable") {
                Text(Int64(model.totalReclaimableBytes), format: .byteCount(style: .file))
                    .monospacedDigit()
            }
            .font(.headline)
        }
        .padding()
    }

    private func usage(for c: StorageCategory) -> CategoryUsage? {
        switch c {
        case .images: return model.usage?.images
        case .containers: return model.usage?.containers
        case .volumes: return model.usage?.volumes
        }
    }
}

private struct StorageCategoryCard: View {
    let category: StorageCategory
    let usage: CategoryUsage
    let onReclaim: () -> Void

    var body: some View {
        GroupBox(category.title) {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Total") {
                    Text(Int64(usage.sizeInBytes), format: .byteCount(style: .file)) }
                LabeledContent("In use") {
                    Text(Int64(usage.inUseBytes), format: .byteCount(style: .file)) }
                LabeledContent("Reclaimable") {
                    Text(Int64(usage.reclaimable), format: .byteCount(style: .file)) }
                if usage.reclaimable > 0 {
                    Button("Reclaim \(usage.reclaimable, format: .byteCount(style: .file))…",
                        action: onReclaim)
                }
            }
            .padding(6)
        }
    }
}
```
> Confirm `ErrorDetail` exposes `headline` and `explanation` (used by other unavailable views — copy the exact property names from `VolumeListView`'s unavailable branch).

- [ ] **Step 2: Build.** Run: `make build`. Expected: success.
- [ ] **Step 3: Commit** `feat(ui): storage dashboard view with reclaim links`.

---

# Phase 3 — Service logs

### Task 8: `LogSource.system`

**Files:** Modify `Sources/CapsuleDomain/LogsModel.swift` (add `static func system`). Test: `Tests/CapsuleUnitTests/LogsModelSourceTests.swift` (extend).

**Interfaces:**
- Produces: `LogSource.system(_ backend:) -> LogSource`. Convention: the system source ignores `id`/`boot`; the `tail: Int?` is interpreted as **minutes** (nil → "5m"), mapped to `--last <n>m` via `followSystemLogs`/`fetchSystemLogs`.

- [ ] **Step 1: Failing test** in `LogsModelSourceTests.swift`:
```swift
@MainActor
func testSystemSourceFetchesViaLastWindow() async {
    let backend = MockBackend()  // systemLogLines = ["apiserver: started","apiserver: listening"]
    let model = LogsModel(source: .system(backend))
    model.follow = false
    model.tail = 60
    model.start(id: "")
    await model.waitForLoad()
    XCTAssertEqual(model.lines.map(\.text), ["apiserver: started", "apiserver: listening"])
}
```

- [ ] **Step 2: Run — expect FAIL.** `make test`.

- [ ] **Step 3: Add the factory.** In `LogSource`:
```swift
/// A source that reads the system service logs. `id`/`boot` are ignored; `tail` (Int?) is
/// interpreted as a minutes window for `--last` (nil → "5m").
public static func system(_ backend: any ContainerBackend) -> LogSource {
    LogSource(
        follow: { _, _ in backend.followSystemLogs() },
        fetch: { _, tail, _ in
            let last = tail.map { "\($0)m" } ?? "5m"
            return try await backend.fetchSystemLogs(last: last)
        }
    )
}
```

- [ ] **Step 4: Run — expect PASS.** `make test`. Confirm existing container/machine LogSource tests still pass (untouched seam).
- [ ] **Step 5: Commit** `feat(domain): system log source for LogsModel`.

### Task 9: `ServiceLogsView`

**Files:** Create `Sources/CapsuleUI/ServiceLogsView.swift`. (Build-verified; GUI smoke later.)

**Interfaces:** Consumes a `LogsModel` (constructed with `.system` source) + `SystemHealth`. Reuses `LogsPaneView`.

- [ ] **Step 1: Implement.** A range picker (5m/1h/1d → minutes 5/60/1440) drives `model.tail`; a follow toggle drives `model.follow`; restart capture on change; a persistent info banner; reuse `LogsPaneView`.
```swift
//  ServiceLogsView.swift … (header)
import CapsuleDomain
import SwiftUI

struct ServiceLogsView: View {
    @Bindable var model: LogsModel
    let isRunning: Bool
    @State private var rangeMinutes = 5

    private let ranges: [(String, Int)] = [("5m", 5), ("1h", 60), ("1d", 1440)]

    var body: some View {
        VStack(spacing: 0) {
            banner
            controls
            Divider()
            LogsPaneView(model: model)   // confirm LogsPaneView's exact init/param name
        }
        .task { reload() }
    }

    private var banner: some View {
        Label(
            "Empty logs can be normal — some startup modes write only to files, not the unified log.",
            systemImage: "info.circle")
            .font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary.opacity(0.4))
    }

    private var controls: some View {
        HStack {
            Picker("Window", selection: $rangeMinutes) {
                ForEach(ranges, id: \.1) { Text($0.0).tag($0.1) }
            }
            .pickerStyle(.segmented).fixedSize()
            Toggle("Follow", isOn: $model.follow)
            Spacer()
            Button("Refresh") { reload() }
        }
        .padding(8)
        .onChange(of: rangeMinutes) { _, _ in reload() }
        .onChange(of: model.follow) { _, _ in reload() }
    }

    private func reload() {
        model.tail = rangeMinutes
        model.start(id: "")
    }
}
```
> Verify `LogsPaneView`'s initializer (param label) and match it. If `LogsPaneView` requires more than `model`, pass the minimal set used by the container logs pane.

- [ ] **Step 2: Build.** `make build`.
- [ ] **Step 3: Commit** `feat(ui): service logs view with empty-is-not-failure banner`.

---

# Phase 4 — About / Diagnostics

### Task 10: `AboutModel`

**Files:** Create `Sources/CapsuleDomain/AboutModel.swift`. Test: `Tests/CapsuleUnitTests/AboutModelTests.swift`.

**Interfaces:**
- Consumes: `ContainerBackend.systemComponentVersions()`, `ComponentVersion`, `SemanticVersion` (from `CapsuleBackend`).
- Produces: `AboutModel` with `components: [ComponentVersion]`, `compatibilityWarnings: [String]`, `bugReportText: String`, `refresh() async`. `compatibilityWarnings` is non-empty when the parsed client vs server major.minor differ.

- [ ] **Step 1: Failing test:**
```swift
@MainActor
final class AboutModelTests: XCTestCase {
    func testLoadsComponentsAndBuildsReport() async {
        let backend = MockBackend()
        let model = AboutModel(backend: backend, normalize: { _ in .placeholder },
            appVersion: "0.10.0", osVersion: "macOS 26.0")
        await model.refresh()
        XCTAssertEqual(model.components.count, 2)
        XCTAssertTrue(model.bugReportText.contains("container"))
        XCTAssertTrue(model.bugReportText.contains("0.10.0"))
    }
    func testCompatibilityWarningOnVersionSkew() async {
        let backend = MockBackend()
        backend.componentVersions = [
            ComponentVersion(appName: "container", version: "1.0.0", buildType: "release", commit: "a"),
            ComponentVersion(appName: "container-apiserver",
                version: "container-apiserver version 0.9.0 (build: release, commit: b)",
                buildType: "release", commit: "b")]
        let model = AboutModel(backend: backend, normalize: { _ in .placeholder },
            appVersion: "0.10.0", osVersion: "macOS 26.0")
        await model.refresh()
        XCTAssertFalse(model.compatibilityWarnings.isEmpty)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `make test`.

- [ ] **Step 3: Implement.**
```swift
//  AboutModel.swift … (header + "must remain free of UI / Process" note)
import CapsuleBackend
import Foundation
import Observation

@MainActor
@Observable
public final class AboutModel {
    public private(set) var components: [ComponentVersion] = []
    public private(set) var loadFailed: String?

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let appVersion: String
    private let osVersion: String

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel.defaultNormalize,
        appVersion: String,
        osVersion: String
    ) {
        self.backend = backend
        self.normalize = normalize
        self.appVersion = appVersion
        self.osVersion = osVersion
    }

    public func refresh() async {
        do { components = try await backend.systemComponentVersions(); loadFailed = nil }
        catch { loadFailed = normalize(error).detail.explanation }
    }

    /// First numeric `major.minor.patch` found in a (possibly messy) version string.
    private func semver(_ s: String) -> SemanticVersion? {
        // Reuse SemanticVersion's parser if it tolerates a prefix; otherwise extract the first
        // <int>.<int>(.<int>)? token. Confirm SemanticVersion's API and use it.
        SemanticVersion(parsing: s)
    }

    public var compatibilityWarnings: [String] {
        guard
            let client = components.first(where: { $0.appName == "container" })?.version,
            let server = components.first(where: { $0.appName.contains("apiserver") })?.version,
            let cv = semver(client), let sv = semver(server)
        else { return [] }
        if cv.major != sv.major || cv.minor != sv.minor {
            return ["CLI (\(client)) and API server differ in version — update both to matching releases."]
        }
        return []
    }

    public var bugReportText: String {
        var lines = ["Capsule \(appVersion)", osVersion, ""]
        lines += components.map { "\($0.appName): \($0.version) (\($0.buildType), \($0.commit))" }
        if !compatibilityWarnings.isEmpty { lines += [""] + compatibilityWarnings }
        return lines.joined(separator: "\n")
    }
}
```
> Confirm `SemanticVersion`'s real initializer name (grep `SemanticVersion(`); adapt `semver(_:)` to it. If it cannot parse a prefixed string, extract the first `\d+\.\d+(\.\d+)?` substring first.

- [ ] **Step 4: Run — expect PASS.** `make test`.
- [ ] **Step 5: Commit** `feat(domain): about/diagnostics model + bug report + compat warnings`.

### Task 11: `AboutDiagnosticsView`

**Files:** Create `Sources/CapsuleUI/AboutDiagnosticsView.swift`. (Build-verified.)

- [ ] **Step 1: Implement** — component table, OS/app version, compatibility warnings, Copy bug report (`NSPasteboard`), Export Diagnostics (calls an injected `onExportDiagnostics: () -> Void`, wired to the existing `.exportDiagnostics` recovery action).
```swift
//  AboutDiagnosticsView.swift … (header)
import CapsuleDomain
import SwiftUI

struct AboutDiagnosticsView: View {
    @Bindable var model: AboutModel
    let onExportDiagnostics: () -> Void

    var body: some View {
        Form {
            Section("Components") {
                ForEach(model.components) { c in
                    LabeledContent(c.appName) {
                        VStack(alignment: .trailing) {
                            Text(c.version).monospaced()
                            Text("\(c.buildType) · \(c.commit)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !model.compatibilityWarnings.isEmpty {
                Section("Compatibility") {
                    ForEach(model.compatibilityWarnings, id: \.self) { w in
                        Label(w, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
            }
            Section {
                HStack {
                    Button("Copy Bug Report") {
                        let pb = NSPasteboard.general; pb.clearContents()
                        pb.setString(model.bugReportText, forType: .string)
                    }
                    Button("Export Diagnostics…", action: onExportDiagnostics)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.refresh() }
    }
}
```

- [ ] **Step 2: Build.** `make build`.
- [ ] **Step 3: Commit** `feat(ui): about/diagnostics pane`.

---

# Phase 5 — System pane restructure + wiring (lights up Storage/Logs/About)

### Task 12: TabView restructure + composition root

**Files:**
- Modify: `Sources/CapsuleUI/SystemDetailView.swift` (wrap existing content in an Overview tab; add Storage/Service Logs/About tabs)
- Modify: `Sources/CapsuleApp/AppEnvironment.swift` (construct `StorageDashboardModel`, `AboutModel`, a system `LogsModel`; wire `onReclaim` + diagnostics export; add fields)
- Modify: `Sources/CapsuleUI/ContentColumnView.swift` (pass the new models to `SystemDetailView`)
- Modify whichever types thread the models down (`CapsuleScene` → `RootView` → `AppShellView` → `ContentColumnView`), following how `machineBrowserModel` etc. are threaded.

**Interfaces:**
- Consumes: Task 6/8/10 models + Task 7/9/11 views.
- Produces: a `SystemDetailView` that takes `health`, `actions`, `storageModel`, `serviceLogsModel`, `aboutModel`.

- [ ] **Step 1: Restructure `SystemDetailView`** to a `TabView` keeping the existing Form as the **Overview** tab:
```swift
struct SystemDetailView: View {
    let health: SystemHealth
    let actions: ShellActions
    let storageModel: StorageDashboardModel
    let serviceLogsModel: LogsModel
    let aboutModel: AboutModel

    var body: some View {
        TabView {
            overview.tabItem { Label("Overview", systemImage: "heart.text.square") }
            StorageDashboardView(model: storageModel)
                .tabItem { Label("Storage", systemImage: "internaldrive") }
            ServiceLogsView(model: serviceLogsModel, isRunning: health.isRunning)
                .tabItem { Label("Service Logs", systemImage: "doc.text.magnifyingglass") }
            AboutDiagnosticsView(aboutModel: aboutModel,
                onExportDiagnostics: { actions.recover(.exportDiagnostics) })
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }

    private var overview: some View {
        Form { /* the existing Status + Start/Stop/Export sections, unchanged */ }
            .formStyle(.grouped)
    }
}
```
> Move the current `body`'s `Form { … }` verbatim into `overview`. Match `AboutDiagnosticsView`'s real param label (`aboutModel:` vs `model:`) to whatever Task 11 used — keep them consistent.

- [ ] **Step 2: Construct models in `AppEnvironment.live()`** (after `taskCenter`/browser models exist):
```swift
let storageDashboardModel = StorageDashboardModel(
    backend: backend,
    normalize: { ErrorNormalizer.normalize($0) },
    onReclaim: { category in
        switch category {
        case .images: Task { _ = await imageActionsModel.prune(all: true) }
        case .containers: Task { _ = await lifecycleModel.prune() }
        case .volumes: Task { _ = await volumeActionsModel.prune() }
        }
        Task { await storageDashboardModelRef?.refresh() }   // see note
    })
let serviceLogsModel = LogsModel(source: .system(backend))
let aboutModel = AboutModel(
    backend: backend,
    normalize: { ErrorNormalizer.normalize($0) },
    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—",
    osVersion: ProcessInfo.processInfo.operatingSystemVersionString)
```
> The `onReclaim` closure references `storageDashboardModel` before it's assigned. Resolve exactly as the existing `imageActionsModel`/`browserModel` mutual references do (they use `reloadList: { await imageBrowserModel.refresh() }` capturing a `let` defined earlier). Simplest: drop the self-refresh line and instead have `StorageDashboardView` re-`refresh()` via `.task`/a refresh button; OR declare `storageDashboardModel` first with `onReclaim` set afterward if the model exposes it. **Pick the approach that matches this file's existing mutual-reference handling and keep `onReclaim` pure-delegating** (it already triggers the prune flow; the dashboard's own Refresh button covers re-read). Confirm `imageActionsModel.prune(all:)`, `lifecycleModel.prune()`, `volumeActionsModel.prune()` signatures (grep) and adapt the calls.

- [ ] **Step 3: Add the three to `AppEnvironment`'s stored properties + initializer + the `live()` return**, mirroring the existing fields (e.g. `volumeBrowserModel`). Thread them to where `SystemDetailView` is built.

- [ ] **Step 4: Pass them through `ContentColumnView`** to `SystemDetailView(health:actions:storageModel:serviceLogsModel:aboutModel:)`. Follow how `ContentColumnView` already receives models (it routes `.system` → `SystemDetailView`); add the new params to its init and to the call site in `AppShellView`.

- [ ] **Step 5: Build + full test.** Run: `make build` then `make test`. Expected: green (no behavior tests change; this is wiring).

- [ ] **Step 6: Commit** `feat(ui): System pane tabs (Overview/Storage/Logs/About) + wiring`.

---

# Phase 6 — Kernel manager (Advanced Settings)

### Task 13: `KernelManagerModel`

**Files:** Create `Sources/CapsuleDomain/KernelManagerModel.swift`. Test: `Tests/CapsuleUnitTests/KernelManagerModelTests.swift`.

**Interfaces:**
- Consumes: `ContainerBackend.systemProperties()` (current kernel), `setKernel(_:)`, `TaskCenter`, `KernelConfiguration`/`KernelSource`/`KernelArch`.
- Produces: `KernelManagerModel` with `currentKernelSummary: String?`, a `KernelDraft` (`mode: KernelSourceMode`, `binaryPath`, `tarURL`, `tarMember`, `arch`, `force`), `validationMessage: String?`, `commandPreview: String`, `recoveryGuidance: String` (static), `loadCurrent() async`, `install()`; `KernelSourceMode { recommended, localFile, remoteTar }`.

- [ ] **Step 1: Failing test:**
```swift
@MainActor
final class KernelManagerModelTests: XCTestCase {
    func testCommandPreviewForLocalFile() {
        let m = KernelManagerModel(backend: MockBackend(), taskCenter: TaskCenter())
        m.draft.mode = .localFile
        m.draft.binaryPath = "/k/vmlinux"
        m.draft.arch = .arm64
        XCTAssertEqual(m.commandPreview,
            "container system kernel set --arch arm64 --binary /k/vmlinux")
    }
    func testValidationRequiresPathForLocalFile() {
        let m = KernelManagerModel(backend: MockBackend(), taskCenter: TaskCenter())
        m.draft.mode = .localFile
        XCTAssertNotNil(m.validationMessage)       // empty path → message
        m.draft.binaryPath = "/k/vmlinux"
        XCTAssertNil(m.validationMessage)
    }
    func testRecommendedIsAlwaysValid() {
        let m = KernelManagerModel(backend: MockBackend(), taskCenter: TaskCenter())
        m.draft.mode = .recommended
        XCTAssertNil(m.validationMessage)
    }
    func testInstallRecordsConfigurationViaBackend() async {
        let backend = MockBackend()
        let center = TaskCenter()
        let m = KernelManagerModel(backend: backend, taskCenter: center)
        m.draft.mode = .recommended
        m.install()
        await center.activeTasks.first?.wait()
        XCTAssertEqual(backend.lastKernelConfiguration?.source, .recommended)
    }
    func testLoadCurrentReadsKernelSection() async {
        let m = KernelManagerModel(backend: MockBackend(), taskCenter: TaskCenter())
        await m.loadCurrent()
        XCTAssertNotNil(m.currentKernelSummary)     // from properties [kernel].binaryPath
    }
}
```
> `KernelSource` needs `Equatable` (already declared) for `.source == .recommended`.

- [ ] **Step 2: Run — expect FAIL.** `make test`.

- [ ] **Step 3: Implement.**
```swift
//  KernelManagerModel.swift … (header + "free of UI / Process" note)
import CapsuleBackend
import Foundation
import Observation

public enum KernelSourceMode: String, Sendable, CaseIterable, Identifiable {
    case recommended, localFile, remoteTar
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .recommended: return "Recommended (safe)"
        case .localFile: return "Local file"
        case .remoteTar: return "Remote tar"
        }
    }
}

@MainActor
@Observable
public final class KernelManagerModel {
    public struct Draft {
        public var mode: KernelSourceMode = .recommended
        public var binaryPath = ""
        public var tarURL = ""
        public var tarMember = ""
        public var arch: KernelArch = .arm64
        public var force = false
    }

    public var draft = Draft()
    public private(set) var currentKernelSummary: String?

    public let recoveryGuidance =
        "Installing an incompatible kernel can stop containers and machines from booting. "
        + "If that happens, restore a known-good kernel with the Recommended option, or run "
        + "`container system kernel set --recommended` in Terminal."

    private let backend: any ContainerBackend
    private let taskCenter: TaskCenter
    private let normalize: @Sendable (any Error) -> CapsuleError

    public init(
        backend: any ContainerBackend,
        taskCenter: TaskCenter,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel.defaultNormalize
    ) {
        self.backend = backend
        self.taskCenter = taskCenter
        self.normalize = normalize
    }

    public func loadCurrent() async {
        guard let props = try? await backend.systemProperties() else { return }
        if let k = props.section("kernel") {
            let path = k.entries.first { $0.key == "binaryPath" }?.value
            let url = k.entries.first { $0.key == "url" }?.value
            currentKernelSummary = path ?? url
        }
    }

    private var configuration: KernelConfiguration {
        let source: KernelSource
        switch draft.mode {
        case .recommended: source = .recommended
        case .localFile: source = .localBinary(path: draft.binaryPath)
        case .remoteTar:
            source = .remoteTar(url: draft.tarURL, member: draft.tarMember.isEmpty ? nil : draft.tarMember)
        }
        return KernelConfiguration(source: source, arch: draft.arch, force: draft.force)
    }

    public var validationMessage: String? {
        switch draft.mode {
        case .recommended: return nil
        case .localFile:
            return draft.binaryPath.isEmpty ? "Choose a kernel file." : nil
        case .remoteTar:
            return draft.tarURL.isEmpty ? "Enter a tar archive URL or path." : nil
        }
    }

    public var commandPreview: String {
        "container " + configuration.arguments.joined(separator: " ")
    }

    public func install() {
        let config = configuration
        taskCenter.runStreaming(kind: .systemKernelInstall, title: "Install Kernel") {
            backend.setKernel(config)
        }
    }
}
```

- [ ] **Step 4: Run — expect PASS.** `make test`.
- [ ] **Step 5: Commit** `feat(domain): kernel manager model (sources/validation/preview/install)`.

### Task 14: `KernelSetupSheet` + Advanced tab Kernel section

**Files:** Create `Sources/CapsuleUI/KernelSetupSheet.swift`; create `Sources/CapsuleUI/AdvancedSettingsView.swift` (hosts the Kernel section now; the Configuration section is added in Task 18). (Build-verified.)

- [ ] **Step 1: Implement `KernelSetupSheet`** — source `Picker` (`KernelSourceMode`), conditional fields (local file via an "Choose…" button using `NSOpenPanel`; remote URL + optional member; arch picker; force toggle), the **compatibility warning + `recoveryGuidance`**, the live `commandPreview`, and Install (calls `model.install()`, dismisses; progress shows in Activity). Disable Install when `validationMessage != nil`.
```swift
//  KernelSetupSheet.swift … (header)
import CapsuleDomain
import SwiftUI

struct KernelSetupSheet: View {
    @Bindable var model: KernelManagerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Change Kernel").font(.title3.bold())
            Label(model.recoveryGuidance, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange).font(.callout)
            Picker("Source", selection: $model.draft.mode) {
                ForEach(KernelSourceMode.allCases) { Text($0.title).tag($0) }
            }
            switch model.draft.mode {
            case .recommended:
                Text("Downloads and installs a known-good kernel.").foregroundStyle(.secondary)
            case .localFile:
                HStack {
                    TextField("Kernel file path", text: $model.draft.binaryPath)
                    Button("Choose…") { chooseFile() }
                }
                archAndForce
            case .remoteTar:
                TextField("Tar archive URL or path", text: $model.draft.tarURL)
                TextField("Archive member (optional)", text: $model.draft.tarMember)
                archAndForce
            }
            Text(model.commandPreview).font(.caption.monospaced())
                .textSelection(.enabled).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Install") { model.install(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.validationMessage != nil)
            }
            if let msg = model.validationMessage {
                Text(msg).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(20).frame(width: 460)
    }

    private var archAndForce: some View {
        HStack {
            Picker("Architecture", selection: $model.draft.arch) {
                ForEach(KernelArch.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.fixedSize()
            Toggle("Overwrite existing (--force)", isOn: $model.draft.force)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.draft.binaryPath = url.path }
    }
}
```
- [ ] **Step 2: Implement `AdvancedSettingsView`** with the Kernel section (current kernel readout + "Change Kernel…" presenting the sheet):
```swift
//  AdvancedSettingsView.swift … (header)
import CapsuleDomain
import SwiftUI

struct AdvancedSettingsView: View {
    @Bindable var kernelModel: KernelManagerModel
    // Task 18 adds: let propertiesModel: SystemPropertiesModel
    @State private var showingKernelSheet = false

    var body: some View {
        Form {
            Section("Kernel") {
                LabeledContent("Current kernel", value: kernelModel.currentKernelSummary ?? "—")
                Button("Change Kernel…") { showingKernelSheet = true }
            }
            // Task 18 inserts the Configuration section here.
        }
        .formStyle(.grouped)
        .task { await kernelModel.loadCurrent() }
        .sheet(isPresented: $showingKernelSheet) { KernelSetupSheet(model: kernelModel) }
    }
}
```
- [ ] **Step 3: Build.** `make build`.
- [ ] **Step 4: Commit** `feat(ui): kernel setup sheet + advanced settings (kernel section)`.

### Task 15: Wire Advanced tab into Settings

**Files:** Modify `Sources/CapsuleUI/PreferencesView.swift` (add the Advanced tab + `kernelModel` param), `Sources/CapsuleApp/AppEnvironment.swift` (construct `KernelManagerModel`), `Sources/CapsuleApp/CapsuleScene.swift` (pass it into `PreferencesView`).

- [ ] **Step 1: Construct the model** in `AppEnvironment.live()`:
```swift
let kernelManagerModel = KernelManagerModel(
    backend: backend, taskCenter: taskCenter, normalize: { ErrorNormalizer.normalize($0) })
```
Add to `AppEnvironment` stored props + init + return (mirror existing fields).

- [ ] **Step 2: Add the Advanced tab** to `PreferencesView` (gated):
```swift
AdvancedSettingsView(kernelModel: kernelModel)
    .disabled(!systemHealth.supports(.system))
    .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
```
Add `kernelModel: KernelManagerModel` to `PreferencesView.init`. Update the `Settings { PreferencesView(...) }` call in `CapsuleScene.swift` to pass `kernelModel: env.kernelManagerModel`.

- [ ] **Step 3: Build + full test.** `make build` then `make test`. Expected: green.
- [ ] **Step 4: Commit** `feat(app): wire kernel manager into Advanced settings tab`.

---

# Phase 7 — TOML properties (viewer / editor / validate / export / restart banner)

### Task 16: `PropertyTOML` — scoped in-house TOML lint/parse (Domain, no dependency)

**Files:** Create `Sources/CapsuleDomain/PropertyTOML.swift`. Test: `Tests/CapsuleUnitTests/PropertyTOMLTests.swift`.

Scope: the `container` config is flat sections of `key = value` scalars (string/int/float/bool), `#` comments, and blank lines (verified live). The linter is **advisory and lenient**: it reports definite syntax errors with line numbers, parses recognized lines into ordered sections, and never hard-fails on a line it merely doesn't recognize.

**Interfaces:**
- Produces: `TOMLIssue { line: Int; message: String }`; `PropertyTOML.lint(_ text: String) -> [TOMLIssue]`; `PropertyTOML.parse(_ text: String) -> [String: [String: String]]` (section → key → raw value); `PropertyTOML.changes(from old: String, to new: String) -> [String]` (human-readable added/removed/changed keys, e.g. `"build.cpus: 2 → 4"`).

- [ ] **Step 1: Failing tests:**
```swift
final class PropertyTOMLTests: XCTestCase {
    func testLintCleanConfigHasNoIssues() {
        let toml = "[build]\ncpus = 2\nrosetta = true\n\n[machine]\nmemory = \"16gb\"\n"
        XCTAssertTrue(PropertyTOML.lint(toml).isEmpty)
    }
    func testLintFlagsKeyOutsideSection() {
        XCTAssertEqual(PropertyTOML.lint("cpus = 2\n").first?.line, 1)
    }
    func testLintFlagsMissingEquals() {
        let issues = PropertyTOML.lint("[build]\ncpus 2\n")
        XCTAssertEqual(issues.first?.line, 2)
    }
    func testLintFlagsUnterminatedString() {
        let issues = PropertyTOML.lint("[build]\nname = \"oops\n")
        XCTAssertEqual(issues.first?.line, 2)
    }
    func testParseGroupsSections() {
        let parsed = PropertyTOML.parse("[build]\ncpus = 2\n[machine]\ncpus = 5\n")
        XCTAssertEqual(parsed["build"]?["cpus"], "2")
        XCTAssertEqual(parsed["machine"]?["cpus"], "5")
    }
    func testChangesReportsAddedRemovedChanged() {
        let old = "[build]\ncpus = 2\nmemory = \"2gb\"\n"
        let new = "[build]\ncpus = 4\n[machine]\ncpus = 5\n"
        let changes = PropertyTOML.changes(from: old, to: new)
        XCTAssertTrue(changes.contains { $0.contains("build.cpus") && $0.contains("2") && $0.contains("4") })
        XCTAssertTrue(changes.contains { $0.contains("build.memory") })   // removed
        XCTAssertTrue(changes.contains { $0.contains("machine.cpus") })   // added
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `make test`.

- [ ] **Step 3: Implement** (`Sources/CapsuleDomain/PropertyTOML.swift`):
```swift
//  PropertyTOML.swift … (header + "free of UI / Process" note)
import Foundation

public struct TOMLIssue: Sendable, Equatable, Identifiable {
    public var line: Int
    public var message: String
    public var id: Int { line }
}

/// A deliberately small, lenient linter/parser for the flat `key = value` TOML the
/// `container` config uses (sections, scalar values, `#` comments). Advisory only —
/// Capsule exports config; it never applies it.
public enum PropertyTOML {
    public static func lint(_ text: String) -> [TOMLIssue] {
        var issues: [TOMLIssue] = []
        var inSection = false
        for (idx, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = idx + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("[") {
                if !trimmed.hasSuffix("]") {
                    issues.append(TOMLIssue(line: line, message: "Malformed section header."))
                }
                inSection = true
                continue
            }
            guard let eq = trimmed.firstIndex(of: "=") else {
                issues.append(TOMLIssue(line: line, message: "Expected `key = value`."))
                continue
            }
            if !inSection {
                issues.append(TOMLIssue(line: line, message: "Key is outside any [section]."))
            }
            let value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                issues.append(TOMLIssue(line: line, message: "Missing value."))
            } else if value.hasPrefix("\"") && !(value.count >= 2 && value.hasSuffix("\"")) {
                issues.append(TOMLIssue(line: line, message: "Unterminated string."))
            }
        }
        return issues
    }

    public static func parse(_ text: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        var section = ""
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                section = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                result[section] = result[section] ?? [:]
                continue
            }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            var value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty { result[section, default: [:]][key] = value }
        }
        return result
    }

    public static func changes(from old: String, to new: String) -> [String] {
        let a = parse(old), b = parse(new)
        var out: [String] = []
        let sections = Set(a.keys).union(b.keys).sorted()
        for s in sections {
            let oldKeys = a[s] ?? [:], newKeys = b[s] ?? [:]
            for k in Set(oldKeys.keys).union(newKeys.keys).sorted() {
                switch (oldKeys[k], newKeys[k]) {
                case let (ov?, nv?) where ov != nv: out.append("\(s).\(k): \(ov) → \(nv)")
                case (nil, let nv?): out.append("\(s).\(k): added (\(nv))")
                case (let ov?, nil): out.append("\(s).\(k): removed (was \(ov))")
                default: break
                }
            }
        }
        return out
    }
}
```

- [ ] **Step 4: Run — expect PASS.** `make test`.
- [ ] **Step 5: Commit** `feat(domain): scoped TOML linter/parser for property editing`.

### Task 17: `SystemPropertiesModel`

**Files:** Create `Sources/CapsuleDomain/SystemPropertiesModel.swift`. Test: `Tests/CapsuleUnitTests/SystemPropertiesModelTests.swift`.

**Interfaces:**
- Consumes: `ContainerBackend.systemPropertiesTOML()` + `systemProperties()`, `PropertyTOML`.
- Produces: `SystemPropertiesModel` with `sections: [PropertySection]`, `originalTOML: String`, `editBuffer: String`, `issues: [TOMLIssue]` (`= validate()`), `changeReview: [String]`, `restartRequired: Bool`, `load() async`, `validate()`, `markEdited()`, `exportText: String`, `resetEdits()`.

- [ ] **Step 1: Failing test:**
```swift
@MainActor
final class SystemPropertiesModelTests: XCTestCase {
    func testLoadPopulatesSectionsAndBuffer() async {
        let m = SystemPropertiesModel(backend: MockBackend(), normalize: { _ in .placeholder })
        await m.load()
        XCTAssertFalse(m.sections.isEmpty)
        XCTAssertTrue(m.editBuffer.contains("[build]"))
        XCTAssertFalse(m.restartRequired)
    }
    func testEditingFlagsRestartAndReview() async {
        let m = SystemPropertiesModel(backend: MockBackend(), normalize: { _ in .placeholder })
        await m.load()
        m.editBuffer = m.editBuffer.replacingOccurrences(of: "cpus = 2", with: "cpus = 8")
        m.markEdited()
        XCTAssertTrue(m.restartRequired)
        XCTAssertTrue(m.changeReview.contains { $0.contains("cpus") })
    }
    func testValidateSurfacesIssues() async {
        let m = SystemPropertiesModel(backend: MockBackend(), normalize: { _ in .placeholder })
        await m.load()
        m.editBuffer = "cpus = 2\n"  // key outside section
        m.markEdited()
        XCTAssertFalse(m.issues.isEmpty)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `make test`.

- [ ] **Step 3: Implement.**
```swift
//  SystemPropertiesModel.swift … (header + "free of UI / Process" note)
import CapsuleBackend
import Foundation
import Observation

@MainActor
@Observable
public final class SystemPropertiesModel {
    public private(set) var sections: [PropertySection] = []
    public private(set) var originalTOML = ""
    public var editBuffer = ""
    public private(set) var restartRequired = false
    public private(set) var loadError: String?

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel.defaultNormalize
    ) {
        self.backend = backend
        self.normalize = normalize
    }

    public func load() async {
        do {
            let toml = try await backend.systemPropertiesTOML()
            let props = try await backend.systemProperties()
            originalTOML = toml
            editBuffer = toml
            sections = props.sections
            loadError = nil
        } catch {
            loadError = normalize(error).detail.explanation
        }
    }

    public var issues: [TOMLIssue] { PropertyTOML.lint(editBuffer) }
    public var changeReview: [String] { PropertyTOML.changes(from: originalTOML, to: editBuffer) }
    public var isDirty: Bool { editBuffer != originalTOML }
    public var exportText: String { editBuffer }

    /// Called when the user edits; flips the explicit requires-restart state once changes exist.
    public func markEdited() { if isDirty { restartRequired = true } }

    public func resetEdits() {
        editBuffer = originalTOML
        restartRequired = false
    }
}
```

- [ ] **Step 4: Run — expect PASS.** `make test`.
- [ ] **Step 5: Commit** `feat(domain): system properties model (view/edit/validate/restart state)`.

### Task 18: Configuration section + TOML editor sheet

**Files:** Create `Sources/CapsuleUI/PropertiesEditorSheet.swift`; modify `Sources/CapsuleUI/AdvancedSettingsView.swift` (add the Configuration section + `propertiesModel` param + restart banner). (Build-verified.)

- [ ] **Step 1: `PropertiesEditorSheet`** — a larger editor: `TextEditor($model.editBuffer)` (monospaced), live validation issues, change review list, **Export…** via `NSSavePanel`, and the requires-restart banner. Calls `model.markEdited()` on change.
```swift
//  PropertiesEditorSheet.swift … (header)
import CapsuleDomain
import SwiftUI
import UniformTypeIdentifiers

struct PropertiesEditorSheet: View {
    @Bindable var model: SystemPropertiesModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit Configuration (TOML)").font(.title3.bold())
            if model.restartRequired { restartBanner }
            TextEditor(text: $model.editBuffer)
                .font(.body.monospaced()).frame(minWidth: 560, minHeight: 320)
                .border(.quaternary)
                .onChange(of: model.editBuffer) { _, _ in model.markEdited() }
            if !model.issues.isEmpty {
                ForEach(model.issues) { issue in
                    Label("Line \(issue.line): \(issue.message)", systemImage: "xmark.octagon")
                        .foregroundStyle(.red).font(.caption)
                }
            }
            if !model.changeReview.isEmpty {
                DisclosureGroup("Change review (\(model.changeReview.count))") {
                    ForEach(model.changeReview, id: \.self) { Text($0).font(.caption.monospaced()) }
                }
            }
            HStack {
                Button("Revert") { model.resetEdits() }.disabled(!model.isDirty)
                Spacer()
                Button("Export…") { export() }
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 640, height: 560)
    }

    private var restartBanner: some View {
        Label("Restart services to apply these changes.", systemImage: "arrow.clockwise.circle")
            .foregroundStyle(.orange).font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8).background(.orange.opacity(0.12))
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "container-config.toml"
        if let toml = UTType(filenameExtension: "toml") { panel.allowedContentTypes = [toml] }
        if panel.runModal() == .OK, let url = panel.url {
            try? model.exportText.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
```
- [ ] **Step 2: Extend `AdvancedSettingsView`** — add `propertiesModel`, a Configuration section (read-only section list + "Edit Configuration…" button presenting the sheet), and a restart banner mirrored at the tab level:
```swift
// add stored: @Bindable var propertiesModel: SystemPropertiesModel  + @State showingEditor
Section("Configuration") {
    if propertiesModel.restartRequired {
        Label("Restart services to apply configuration changes.",
            systemImage: "arrow.clockwise.circle").foregroundStyle(.orange)
    }
    ForEach(propertiesModel.sections) { s in
        LabeledContent(s.name, value: "\(s.entries.count) keys")
    }
    Button("Edit Configuration…") { showingEditor = true }
}
// .task { await propertiesModel.load() } ; .sheet(isPresented: $showingEditor) { PropertiesEditorSheet(model: propertiesModel) }
```
- [ ] **Step 3: Build.** `make build`.
- [ ] **Step 4: Commit** `feat(ui): TOML config viewer/editor sheet + restart banner`.

### Task 19: Wire Configuration into Advanced tab

**Files:** Modify `AppEnvironment.swift` (construct `SystemPropertiesModel`), `PreferencesView.swift` (pass it through to `AdvancedSettingsView`), `CapsuleScene.swift` (pass from env).

- [ ] **Step 1: Construct** in `live()`:
```swift
let systemPropertiesModel = SystemPropertiesModel(
    backend: backend, normalize: { ErrorNormalizer.normalize($0) })
```
Add to `AppEnvironment` props/init/return. Pass `propertiesModel:` into `AdvancedSettingsView(kernelModel:propertiesModel:)` via `PreferencesView` (add the param to `PreferencesView.init` and the `CapsuleScene` call site).

- [ ] **Step 2: Build + full test.** `make build` then `make test`. Expected: green.
- [ ] **Step 3: Commit** `feat(app): wire TOML properties into Advanced settings tab`.

---

# Phase 8 — Verification

### Task 20: Gated live integration probe + fixture lock

**Files:** Create `Tests/CapsuleIntegrationTests/SystemSurfaceIntegrationTests.swift` (mirror `MachineIntegrationTests` gating).

- [ ] **Step 1: Write the gated probe** (skips unless `CAPSULE_INTEGRATION=1`): assert `systemDiskUsage()` returns non-negative totals; `systemComponentVersions()` includes a `container` entry; `systemProperties()` has a `build` or `kernel` section and `systemPropertiesTOML()` is non-empty; `fetchSystemLogs(last: "5m")` does not throw (may be empty — that's valid). **Do NOT call `setKernel`** (host-mutating). Include the unconditional `testGuardSkipsCleanlyWithoutEnv` assertion as the sibling file does.
```swift
func testSystemReadsAgainstRealCLI() async throws {
    try requireIntegration()
    let backend = CLIContainerBackend()
    let usage = try await backend.systemDiskUsage()
    XCTAssertGreaterThanOrEqual(usage.images.sizeInBytes, 0)
    let comps = try await backend.systemComponentVersions()
    XCTAssertTrue(comps.contains { $0.appName == "container" })
    let props = try await backend.systemProperties()
    XCTAssertTrue(props.sections.contains { $0.name == "kernel" || $0.name == "build" })
    XCTAssertFalse((try await backend.systemPropertiesTOML()).isEmpty)
    _ = try await backend.fetchSystemLogs(last: "5m")  // empty is OK
}
```
- [ ] **Step 2: Run gated** `CAPSULE_INTEGRATION=1 make test` (or the integration scheme). Capture the real `df`/`version`/`property` output; **diff against the committed fixtures** and correct any field-shape drift (this is the M8-fixture-guard step). Run the default `make test` to confirm the guard skips cleanly.
- [ ] **Step 3: Commit** `test(integration): system surface reads against real container CLI`.

### Task 21: Whole-branch adversarial review + GUI smoke + fixes

- [ ] **Step 1:** Run `make ci` (build + lint + format + arch + full test). Fix anything red. Confirm `ArchitectureGuardTests` green and no UI file contains a forbidden `import Capsule…` substring (incl. comments).
- [ ] **Step 2:** Use `superpowers:requesting-code-review` for a whole-branch adversarial review (the cross-cutting class of bugs per-task review misses — e.g. a model state nobody renders, a leaked follow process, a missing reload). Triage findings by severity; fix Critical/High and re-verify.
- [ ] **Step 3:** Build the `.app` (`make app`) and run a live interactive GUI smoke of the headline flows: System ▸ Storage (reclaimable shown, a Reclaim button triggers the prune confirm), System ▸ Service Logs (renders; with the service stopped the empty banner shows, not an error), System ▸ About (Copy Bug Report), Settings ▸ Advanced ▸ Change Kernel (warning + preview shown; do NOT install), Settings ▸ Advanced ▸ Edit Configuration (edit → validation + change review + restart banner → Export writes a file). Fix any issue found and re-verify.
- [ ] **Step 4: Commit** the fixes; the milestone branch is ready for `finishing-a-development-branch`.

---

## Self-Review

**Spec coverage:**
- Storage dashboard reclaimable/active + cleanup links → Tasks 1, 6, 7, 12 (onReclaim → existing prune). ✓
- Service logs + empty-is-not-failure → Tasks 4, 8, 9, 12. ✓
- About/version + bug reports + compat warnings → Tasks 2, 10, 11, 12. ✓
- Kernel manager (local/remote/recommended) + compat warning + recovery guidance, Advanced Settings → Tasks 5, 13, 14, 15. ✓
- TOML viewer/editor reads/validates/exports + restart banner + change review → Tasks 3, 16, 17, 18, 19. ✓
- Activity-pane/OSLog integration for logs → Task 9 reuses `LogsPaneView` (Activity logs infra); kernel install → `TaskCenter` task (Task 5/13). ✓
- Gating + composition root + errors → Tasks 12, 15, 19 (`.disabled(!supports(.system))`, `normalize`). ✓

**Placeholder scan:** Code blocks are complete; the few "confirm the exact name" notes point at real existing symbols to match (`ErrorDetail`, `LogsPaneView` init, `SemanticVersion(...)`, prune signatures, `MachineConfiguration` host module) — each is a lookup, not deferred logic. No "TODO/handle edge cases/etc." remain.

**Type consistency:** `StorageUsage`/`CategoryUsage` (Task 1) consumed by `StorageDashboardModel` (6) + view (7). `ComponentVersion` (2) → `AboutModel` (10) → view (11). `SystemProperties`/`PropertySection`/`PropertyEntry` (3) → `SystemPropertiesModel` (17) + kernel current-readout (13). `KernelConfiguration`/`KernelSource`/`KernelArch` (5) → `KernelManagerModel` (13). `LogSource.system` (8) ← `fetchSystemLogs`/`followSystemLogs` (4). `OperationKind.systemKernelInstall` (5) ← `KernelManagerModel.install` (13). `PropertyTOML.{lint,parse,changes}`/`TOMLIssue` (16) → `SystemPropertiesModel` (17) + editor (18). All names match across tasks.
