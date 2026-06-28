# Milestone 5B · Non-destructive lifecycle (start / stop / stats) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the non-destructive container lifecycle — `start` (+ read-only attach interim), `stop` (graceful with timeout/signal options + hang detection + interim Force Stop via `stop -t 0`), and `stats` (live pane + compact chips + one-shot snapshot) — backed by an expanded `ContainerBackend` port and tested against `MockBackend`.

**Architecture:** Ports & Adapters (UI → Domain → Backend port; adapter `CapsuleCLIBackend`; root `CapsuleApp`). New Backend value types are Foundation-only and mapped by the domain into domain types before the UI; domain models are `@Observable @MainActor`. Destructive actions (kill/delete/prune/export), confirmation sheets, and the real embedded terminal are explicitly **out of scope** (5C / M6).

**Tech Stack:** Swift 6, SwiftUI (macOS 26+), `Observation`, structured concurrency (`Task`, `AsyncThrowingStream`, `ContinuousClock`), XCTest. Build/test via `Makefile`.

## Global Constraints

- **Arch guard** (tests + `Scripts/check-architecture.sh`): `CapsuleUI` imports no Backend module; `CapsuleDomain` imports no UI and no `Foundation.Process`. No Backend wire type may appear in a `CapsuleUI` signature. The domain may import `CapsuleBackend` (it already does).
- License header on every file (pre-commit `license headers`). `swift-format --strict` clean. Zero-warning build.
- Tests under Xcode toolchain: prefix `swift test` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; filter with `--filter <Suite>`. Full gate: `make ci`.
- TDD: failing test → watch fail → minimal impl → watch pass → commit. End commit messages with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Decisions baked in:** terminal = M6 (after 5C); hang escalation = hybrid (5B ships detection + working interim Force Stop via `stop -t 0` + `container kill` clipboard copy; true destructive `kill` Force Stop with confirmation is 5C); retry-in-terminal interim = clipboard copy + activity note; signal stays `String`/`nil`-default; bulk = domain loop; stats timestamp stamped in-domain; success → activity-log line.
- **CLI facts (verified):** `stop [-s <sig>] [-t <sec> default 5] <ids>`; `stats [<ids>] --format json [--no-stream]` → JSON array of all-optional `ContainerStats` (only `id` required, cumulative `cpuUsageUsec`); empty = `[]`; stop/kill/export exit 1 on failure; `inspect` takes no `--format` (already fixed). Local containers can't run (no kernel) → lenient parsers, best-effort `runFailed`.

---

### Task 1: Backend value types — `StopOptions`, `ContainerStatsSample`

**Files:**
- Create: `Sources/CapsuleBackend/BackendLifecycleTypes.swift`
- Test: `Tests/CapsuleUnitTests/MockBackendTests.swift` (a small type assertion; full behavior in later tasks)

**Interfaces — Produces:**
- `struct StopOptions: Sendable, Equatable { var timeout: Int?; var signal: String?; static let `default`; static let forced }`
- `struct ContainerStatsSample: Sendable, Equatable, Identifiable, Codable` with `id: String` + optional `UInt64` metrics.

- [ ] **Step 1: Write the failing test** — add to `MockBackendTests`:

```swift
func testStopOptionsConstants() {
    XCTAssertEqual(StopOptions.default, StopOptions(timeout: nil, signal: nil))
    XCTAssertEqual(StopOptions.forced, StopOptions(timeout: 0, signal: nil))
}
```

- [ ] **Step 2: Run → fail** (`StopOptions` undefined).
Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter MockBackendTests`

- [ ] **Step 3: Implement** — create `BackendLifecycleTypes.swift`:

```swift
//
//  BackendLifecycleTypes.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Foundation-only value types for the container lifecycle port methods. The domain maps
//  these into its own types before they reach the UI (the arch guard forbids Backend types
//  in CapsuleUI signatures).

import Foundation

/// Options for a graceful stop. `signal` is a raw token (e.g. "TERM") because the Backend
/// layer cannot import the domain's `ProcessSignal`.
public struct StopOptions: Sendable, Equatable {
    public var timeout: Int?
    public var signal: String?

    public init(timeout: Int? = nil, signal: String? = nil) {
        self.timeout = timeout
        self.signal = signal
    }

    /// The CLI defaults (TERM, then kill after 5 s).
    public static let `default` = StopOptions(timeout: nil, signal: nil)
    /// Immediate force via the non-destructive stop verb (`stop -t 0`).
    public static let forced = StopOptions(timeout: 0, signal: nil)
}

/// An all-optional mirror of the CLI's `ContainerStats` (verified against apple/container
/// source: only `id` is required; every metric is an optional cumulative `UInt64`). Carries
/// no CPU% and no timestamp — the domain computes/stamps both.
public struct ContainerStatsSample: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var cpuUsageUsec: UInt64?
    public var memoryUsageBytes: UInt64?
    public var memoryLimitBytes: UInt64?
    public var networkRxBytes: UInt64?
    public var networkTxBytes: UInt64?
    public var blockReadBytes: UInt64?
    public var blockWriteBytes: UInt64?
    public var numProcesses: UInt64?

    public init(
        id: String,
        cpuUsageUsec: UInt64? = nil,
        memoryUsageBytes: UInt64? = nil,
        memoryLimitBytes: UInt64? = nil,
        networkRxBytes: UInt64? = nil,
        networkTxBytes: UInt64? = nil,
        blockReadBytes: UInt64? = nil,
        blockWriteBytes: UInt64? = nil,
        numProcesses: UInt64? = nil
    ) {
        self.id = id
        self.cpuUsageUsec = cpuUsageUsec
        self.memoryUsageBytes = memoryUsageBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.networkRxBytes = networkRxBytes
        self.networkTxBytes = networkTxBytes
        self.blockReadBytes = blockReadBytes
        self.blockWriteBytes = blockWriteBytes
        self.numProcesses = numProcesses
    }
}
```

- [ ] **Step 4: Run → pass.**
- [ ] **Step 5: Commit** — `feat(backend): StopOptions + ContainerStatsSample value types`.

---

### Task 2: Port protocol + MockBackend — stop-with-options, stats (one-shot + stream)

**Files:**
- Modify: `Sources/CapsuleBackend/ContainerBackend.swift`, `Sources/CapsuleBackend/MockBackend.swift`
- Test: `Tests/CapsuleUnitTests/MockBackendTests.swift`

**Interfaces:**
- Consumes: `StopOptions`, `ContainerStatsSample` (Task 1).
- Produces on `ContainerBackend`: `func stopContainer(id:options:) async throws` (replaces `stopContainer(id:)`); extension `stopContainer(id:)` → `.default`; `func containerStats(ids: [String]) async throws -> [ContainerStatsSample]`; `func streamContainerStats(ids: [String], interval: Duration) -> AsyncThrowingStream<[ContainerStatsSample], Error>`.
- MockBackend: implements all; adds `var sampleStats: [ContainerStatsSample]`, `var startFailure: BackendError?`, records `lastStopOptions`; **removes** the old `stopContainer(id:)`.

- [ ] **Step 1: Write failing tests** — add to `MockBackendTests`:

```swift
func testStopRecordsOptions() async throws {
    let backend = MockBackend()
    try await backend.stopContainer(id: "a1b2c3d4", options: StopOptions(timeout: 3, signal: "TERM"))
    XCTAssertEqual(backend.lastStopOptions, StopOptions(timeout: 3, signal: "TERM"))
    let stopped = try await backend.listContainers(all: true).first { $0.id == "a1b2c3d4" }
    XCTAssertEqual(stopped?.state, "stopped")
}

func testStopConvenienceUsesDefault() async throws {
    let backend = MockBackend()
    try await backend.stopContainer(id: "a1b2c3d4")
    XCTAssertEqual(backend.lastStopOptions, .default)
}

func testStatsSnapshotReturnsSeededSamples() async throws {
    let backend = MockBackend(sampleStats: [ContainerStatsSample(id: "a1b2c3d4", cpuUsageUsec: 10)])
    let samples = try await backend.containerStats(ids: ["a1b2c3d4"])
    XCTAssertEqual(samples.map(\.id), ["a1b2c3d4"])
}

func testStatsStreamEmitsThenFinishes() async throws {
    let backend = MockBackend(sampleStats: [ContainerStatsSample(id: "a1b2c3d4", cpuUsageUsec: 10)])
    var batches = 0
    for try await batch in backend.streamContainerStats(ids: ["a1b2c3d4"], interval: .milliseconds(1)) {
        XCTAssertEqual(batch.first?.id, "a1b2c3d4")
        batches += 1
        if batches >= 2 { break }   // breaking cancels the stream
    }
    XCTAssertGreaterThanOrEqual(batches, 2)
}
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Update the protocol.** In `ContainerBackend.swift`, replace `func stopContainer(id: String) async throws` with:

```swift
    func stopContainer(id: String, options: StopOptions) async throws
```

and add to the `// MARK: Containers` block:

```swift
    /// One-shot resource statistics for the given containers.
    func containerStats(ids: [String]) async throws -> [ContainerStatsSample]

    /// Streams resource statistics, polling `interval` between one-shot reads. The stream
    /// finishes cleanly when cancelled (consumer breaks out / task cancelled).
    func streamContainerStats(ids: [String], interval: Duration)
        -> AsyncThrowingStream<[ContainerStatsSample], Error>
```

In the existing `extension ContainerBackend` (with the `listContainers()` convenience), add:

```swift
    /// Convenience: stop with default options (CLI default signal + timeout).
    public func stopContainer(id: String) async throws {
        try await stopContainer(id: id, options: .default)
    }
```

- [ ] **Step 4: Update `MockBackend`.** Add stored properties near the top:

```swift
    public var startFailure: BackendError?
    public private(set) var lastStopOptions: StopOptions?
    private var sampleStats: [ContainerStatsSample]
```

Add `sampleStats: [ContainerStatsSample] = MockBackend.sampleStatsDefault` to `init`'s parameters and assign `self.sampleStats = sampleStats`. Replace `stopContainer` and add the stats methods (remove the old arity-1 `stopContainer`):

```swift
    public func stopContainer(id: String, options: StopOptions) async throws {
        try withState { state in
            state.lastStopOptions = options
            state.mutateContainer(id) {
                $0.state = "stopped"
                $0.ip = nil
            }
        }
    }

    public func containerStats(ids: [String]) async throws -> [ContainerStatsSample] {
        try withState { state in
            ids.isEmpty ? state.sampleStats : state.sampleStats.filter { ids.contains($0.id) }
        }
    }

    public func streamContainerStats(ids: [String], interval: Duration)
        -> AsyncThrowingStream<[ContainerStatsSample], Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        let batch = try await containerStats(ids: ids)
                        if Task.isCancelled { break }
                        continuation.yield(batch)
                        try await Task.sleep(for: interval)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
```

Add the seed near `sampleContainers`:

```swift
    public static let sampleStatsDefault: [ContainerStatsSample] = [
        ContainerStatsSample(
            id: "a1b2c3d4", cpuUsageUsec: 1_000_000, memoryUsageBytes: 64_000_000,
            memoryLimitBytes: 512_000_000, networkRxBytes: 1024, networkTxBytes: 2048,
            numProcesses: 3),
        ContainerStatsSample(
            id: "0c1d2e3f", cpuUsageUsec: 500_000, memoryUsageBytes: 32_000_000,
            memoryLimitBytes: 256_000_000, numProcesses: 1),
    ]
```

If a `startContainer` failure hook is wanted, also gate `startContainer` on `startFailure` (optional; the `failure` global already covers throws). For 5B keep `startFailure` available but `start` uses the existing `withState` (honors `failure`); skip a separate hook unless a test needs container-specific start failure — if so, throw `startFailure` first in `startContainer`.

- [ ] **Step 5: Run → pass.** Fix any other call sites the protocol change broke (search `stopContainer(id:`): the convenience extension preserves them, but **delete** any concrete arity-1 override.

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` then the filter.

- [ ] **Step 6: Commit** — `feat(backend): stop-with-options + container stats (snapshot + stream) on the port`.

---

### Task 3: CLICommand + ArgumentBuilder — stop options & stats argv

**Files:**
- Modify: `Sources/CapsuleCLIBackend/CLICommand.swift`, `Sources/CapsuleCLIBackend/ArgumentBuilder.swift`
- Test: `Tests/CapsuleUnitTests/CLICommandTests.swift`, `Tests/CapsuleUnitTests/ArgumentBuilderTests.swift`

**Interfaces:**
- Produces: `CLICommand.stopContainer(id:options:) -> [String]`, `CLICommand.containerStats(ids:) -> [String]`, `ArgumentBuilder.adding(contentsOf: [String]) -> ArgumentBuilder`.

- [ ] **Step 1: Write failing tests.** In `ArgumentBuilderTests`, add (match the file's existing style):

```swift
func testAddingContentsOfAppendsAll() {
    XCTAssertEqual(ArgumentBuilder("stats").adding(contentsOf: ["a", "b"]).arguments, ["stats", "a", "b"])
    XCTAssertEqual(ArgumentBuilder("stats").adding(contentsOf: []).arguments, ["stats"])
}
```

In `CLICommandTests`, replace `testContainerLifecycle`'s stop assertion and add stats. Change the stop line to:

```swift
        XCTAssertEqual(CLICommand.stopContainer(id: "abc", options: .default), ["stop", "abc"])
        XCTAssertEqual(
            CLICommand.stopContainer(id: "abc", options: StopOptions(timeout: 0, signal: nil)),
            ["stop", "--time", "0", "abc"])
        XCTAssertEqual(
            CLICommand.stopContainer(id: "abc", options: StopOptions(timeout: 3, signal: "TERM")),
            ["stop", "--time", "3", "--signal", "TERM", "abc"])
```

Add a stats test:

```swift
    func testStats() {
        XCTAssertEqual(
            CLICommand.containerStats(ids: ["a", "b"]),
            ["stats", "--no-stream", "--format", "json", "a", "b"])
        XCTAssertEqual(
            CLICommand.containerStats(ids: []),
            ["stats", "--no-stream", "--format", "json"])
    }
```

(`CLICommandTests` must `import CapsuleBackend` for `StopOptions` — add it.)

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement.** In `ArgumentBuilder.swift`, add (next to `adding(_:)`):

```swift
    /// Appends each element of a sequence (the variadic `adding` can't splat an array).
    public func adding(contentsOf values: [String]) -> ArgumentBuilder {
        var copy = self
        copy.storage.append(contentsOf: values)
        return copy
    }
```

(Adjust to the builder's actual internal storage name — read the file; it accumulates into an `arguments`-backing array. Mirror the existing `adding(_:)`/`flag`/`option` mutation style exactly.)

In `CLICommand.swift`, replace `stopContainer` and add stats (and `import CapsuleBackend` if not present):

```swift
    public static func stopContainer(id: String, options: StopOptions) -> [String] {
        ArgumentBuilder("stop")
            .flag("--time", options.timeout.map(String.init))
            .flag("--signal", options.signal)
            .adding(id)
            .arguments
    }
```

If `ArgumentBuilder.flag(_:_:)` does not accept an optional value, use `.option`/conditional adds matching the file's API; the argv result must be exactly `["stop", "--time", "0", "abc"]` etc. (flags omitted when `nil`). Add:

```swift
    public static func containerStats(ids: [String]) -> [String] {
        ArgumentBuilder("stats").flag("--no-stream").flag("--format", "json")
            .adding(contentsOf: ids).arguments
    }
```

(`--no-stream` is a bare flag; if `flag` needs a value, use the builder's boolean-flag method. Match the existing `--all`/`--follow` style — read `ArgumentBuilder`.)

- [ ] **Step 4: Run → pass.**
- [ ] **Step 5: Commit** — `feat(cli): stop-options + stats argv builders`.

---

### Task 4: Stats wire model + parser

**Files:**
- Modify: `Sources/CapsuleCLIBackend/WireModels.swift`, `Sources/CapsuleCLIBackend/OutputParser.swift`
- Test: `Tests/CapsuleUnitTests/OutputParserTests.swift`

**Interfaces:**
- Produces: `OutputParser.parseStats(_ data: Data) throws -> [ContainerStatsSample]`, internal `CLIContainerStatsRecord` (no `CodingKeys`; keys == property names).

- [ ] **Step 1: Write failing tests** — add to `OutputParserTests`:

```swift
func testParseStatsEmptyArray() throws {
    XCTAssertEqual(try OutputParser.parseStats(Data("[]".utf8)).count, 0)
}

func testParseStatsDecodesSampleAndIsLenient() throws {
    let json = """
    [{"id":"abc","cpuUsageUsec":1000000,"memoryUsageBytes":64000000,"numProcesses":3},
     {"id":"def"},
     {"noId":true}]
    """
    let rows = try OutputParser.parseStats(Data(json.utf8))
    XCTAssertEqual(rows.map(\.id), ["abc", "def"])  // 3rd dropped: missing required id
    XCTAssertEqual(rows.first?.cpuUsageUsec, 1_000_000)
    XCTAssertEqual(rows.first?.numProcesses, 3)
}
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement.** In `WireModels.swift`, add:

```swift
// MARK: - Stats

/// One element of `container stats --format json`. Mirror of the source `ContainerStats`
/// struct; keys equal property names (no custom CodingKeys). Only `id` is required.
struct CLIContainerStatsRecord: Decodable {
    let id: String
    let cpuUsageUsec: UInt64?
    let memoryUsageBytes: UInt64?
    let memoryLimitBytes: UInt64?
    let networkRxBytes: UInt64?
    let networkTxBytes: UInt64?
    let blockReadBytes: UInt64?
    let blockWriteBytes: UInt64?
    let numProcesses: UInt64?
}
```

In `OutputParser.swift`, add to the `// MARK: - Containers` (or a new `// MARK: - Stats`) section:

```swift
    /// Decodes `container stats --format json` into samples, skipping any element whose
    /// schema no longer matches (e.g. missing the required `id`).
    public static func parseStats(_ data: Data) throws -> [ContainerStatsSample] {
        try lossyList(data, decode: CLIContainerStatsRecord.self).map { record in
            ContainerStatsSample(
                id: record.id,
                cpuUsageUsec: record.cpuUsageUsec,
                memoryUsageBytes: record.memoryUsageBytes,
                memoryLimitBytes: record.memoryLimitBytes,
                networkRxBytes: record.networkRxBytes,
                networkTxBytes: record.networkTxBytes,
                blockReadBytes: record.blockReadBytes,
                blockWriteBytes: record.blockWriteBytes,
                numProcesses: record.numProcesses
            )
        }
    }
```

- [ ] **Step 4: Run → pass.**
- [ ] **Step 5: Commit** — `feat(cli): lenient stats JSON parser`.

---

### Task 5: CLIContainerBackend — implement stop-options + stats; remove arity-1 stop

**Files:**
- Modify: `Sources/CapsuleCLIBackend/CLIContainerBackend.swift`
- Test: `Tests/CapsuleUnitTests/CLIContainerBackendTests.swift`

**Interfaces:**
- Consumes Tasks 2–4. Produces the adapter implementations of `stopContainer(id:options:)`, `containerStats(ids:)`, `streamContainerStats(ids:interval:)`.

- [ ] **Step 1: Write failing tests** — update the existing stop assertion in `testLifecycleCommandsIssueCorrectArgv` and add stats argv + stream tests:

```swift
    // inside testLifecycleCommandsIssueCorrectArgv, replace the stop line:
        try await backend.stopContainer(id: "c1", options: StopOptions(timeout: 2, signal: "TERM"))
        XCTAssertEqual(stub.lastCall, ["stop", "--time", "2", "--signal", "TERM", "c1"])

    func testContainerStatsSnapshotArgvAndDecode() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(
            exitCode: 0, stdout: #"[{"id":"c1","cpuUsageUsec":5}]"#, stderr: "")
        let samples = try await makeBackend(stub).containerStats(ids: ["c1"])
        XCTAssertEqual(samples.first?.id, "c1")
        XCTAssertEqual(stub.lastCall, ["stats", "--no-stream", "--format", "json", "c1"])
    }
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement.** In `CLIContainerBackend.swift`, replace `stopContainer` and add stats:

```swift
    public func stopContainer(id: String, options: StopOptions) async throws {
        _ = try await runChecked(CLICommand.stopContainer(id: id, options: options))
    }

    public func containerStats(ids: [String]) async throws -> [ContainerStatsSample] {
        let output = try await runChecked(CLICommand.containerStats(ids: ids))
        return try OutputParser.parseStats(Data(output.stdout.utf8))
    }

    public func streamContainerStats(ids: [String], interval: Duration)
        -> AsyncThrowingStream<[ContainerStatsSample], Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        let batch = try await containerStats(ids: ids)
                        if Task.isCancelled { break }
                        continuation.yield(batch)
                        try await Task.sleep(for: interval)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    if Task.isCancelled { continuation.finish() } else { continuation.finish(throwing: error) }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
```

Delete the old `stopContainer(id:)` method. Ensure no other adapter code references it.

- [ ] **Step 4: Run → pass** (filter `CLIContainerBackendTests`).
- [ ] **Step 5: Commit** — `feat(cli): adapter stop-options + stats (snapshot + polled stream)`.

---

### Task 6: CLIProcessRunner — cancellation propagation on `run`

**Files:**
- Modify: `Sources/CapsuleCLIBackend/CLIProcessRunner.swift`
- Test: `Tests/CapsuleUnitTests/CLIProcessRunnerTests.swift`

**Interfaces:** `run(_:environment:)` now terminates the child when its task is cancelled, so the stats poll's in-flight one-shot is reaped immediately on stream teardown. (`stream(...)` already reaps via `onTermination` — leave it.)

- [ ] **Step 1: Write a failing test** — add to `CLIProcessRunnerTests` (use a long-running real process so cancellation is observable; match the file's existing approach — it runs `/bin/sh`-style helpers):

```swift
func testRunIsCancellable() async throws {
    let runner = CLIProcessRunner(executableURL: URL(fileURLWithPath: "/bin/sleep"))
    let task = Task { try await runner.run(["5"]) }
    task.cancel()
    do {
        _ = try await task.value
        // Either a cancellation throw or a terminated (signal) result is acceptable;
        // the point is it returns promptly, not after 5s.
    } catch {
        // acceptable
    }
}
```

(If the suite has no real-process precedent, place this test behind the same pattern other runner tests use. The assertion that matters: the call returns well under the 5 s sleep — verify by wrapping in a timeout expectation if the suite has one.)

- [ ] **Step 2: Run → fail** (currently waits ~5 s / never cancels).

- [ ] **Step 3: Implement.** Wrap the continuation in a cancellation handler. Refactor `run` so the `Process` is created before the continuation and terminated on cancel:

```swift
    public func run(
        _ arguments: [String],
        environment: [String: String] = [:]
    ) async throws -> CommandResult {
        let process = makeProcess(arguments: arguments, environment: environment)
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let collector = BufferCollector { continuation.resume(returning: $0) }
                process.terminationHandler = { collector.set(exitCode: $0.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: BackendError.executableNotFound(executableURL.path))
                    return
                }
                DispatchQueue.global().async {
                    collector.set(stdout: outPipe.fileHandleForReading.readDataToEndOfFile())
                }
                DispatchQueue.global().async {
                    collector.set(stderr: errPipe.fileHandleForReading.readDataToEndOfFile())
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
```

- [ ] **Step 4: Run → pass** (returns promptly). Run the whole `CLIProcessRunnerTests` suite to confirm no regression.
- [ ] **Step 5: Commit** — `fix(cli): propagate task cancellation to the spawned process in run()`.

---

### Task 7: Domain value types — `ContainerState.stopping` + `Lifecycle.swift`

**Files:**
- Modify: `Sources/CapsuleDomain/Resource.swift` (add `.stopping`)
- Create: `Sources/CapsuleDomain/Lifecycle.swift`
- Test: `Tests/CapsuleUnitTests/DomainModelTests.swift`, new `Tests/CapsuleUnitTests/LifecycleTypesTests.swift`

**Interfaces — Produces:** `ContainerState.stopping`; `LogLine`, `AttachSession`, `ContainerStartResult`, `ContainerMetrics`, `LifecycleNotice`, `StopOutcome`. `ContainerMetrics.init(sample:capturedAt:cpuPercent:)`.

- [ ] **Step 1: Write failing tests** — in `DomainModelTests`:

```swift
func testContainerStateMapsStopping() {
    XCTAssertEqual(Container(summary: ContainerSummary(
        id: "i", name: "n", image: "x", state: "stopping")).state, .stopping)
}
```

Create `LifecycleTypesTests.swift`:

```swift
//
//  LifecycleTypesTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

final class LifecycleTypesTests: XCTestCase {
    func testMetricsMapFromSampleAndComputeMemoryPercent() {
        let sample = ContainerStatsSample(
            id: "c1", memoryUsageBytes: 50, memoryLimitBytes: 200, numProcesses: 2)
        let m = ContainerMetrics(sample: sample, capturedAt: Date(timeIntervalSince1970: 1), cpuPercent: 12.5)
        XCTAssertEqual(m.id, "c1")
        XCTAssertEqual(m.cpuPercent, 12.5)
        XCTAssertEqual(m.memoryPercent ?? -1, 25.0, accuracy: 0.001)
        XCTAssertEqual(m.numProcesses, 2)
    }

    func testAttachSessionRingBufferCap() {
        var session = AttachSession()
        for i in 0..<250 { session.append(LogLine(id: i, stream: .standard, text: "\(i)")) }
        XCTAssertEqual(session.lines.count, 200)
        XCTAssertEqual(session.lines.first?.id, 50)  // oldest 50 trimmed
        XCTAssertTrue(session.isReadOnly)
    }

    func testStartResultOperationStatus() {
        XCTAssertEqual(ContainerStartResult.started(attached: false).operationStatus, .succeeded)
        XCTAssertEqual(ContainerStartResult.backendUnavailable.operationStatus, .backendUnavailable)
        XCTAssertEqual(ContainerStartResult.failedBeforeExecution.operationStatus, .failedBeforeExecution)
    }
}
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement `.stopping`.** In `Resource.swift`, add `case stopping` to `ContainerState` and map it in `init(backendState:)`:

```swift
    case stopping
```
```swift
        case "stopping": self = .stopping
```

- [ ] **Step 4: Implement `Lifecycle.swift`:**

```swift
//
//  Lifecycle.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Domain value types for the non-destructive lifecycle (start/stop/stats). Backend wire
//  types (ContainerStatsSample, OutputLine) are mapped here so they never reach the UI.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`.

import CapsuleBackend
import Foundation

/// A single line of attach/log output. `stream` reflects the *`container logs` CLI
/// process's* stdout/stderr pipe, not the workload's — labelled honestly in the UI.
public struct LogLine: Sendable, Equatable, Identifiable {
    public enum Stream: Sendable, Equatable { case standard, error }
    public var id: Int
    public var stream: Stream
    public var text: String

    public init(id: Int, stream: Stream, text: String) {
        self.id = id
        self.stream = stream
        self.text = text
    }

    public init(id: Int, source: OutputLine.Source, text: String) {
        self.init(id: id, stream: source == .stderr ? .error : .standard, text: text)
    }
}

/// A read-only attach session (interim until M6's embedded terminal). `isReadOnly` is the
/// seam M6 flips. `lines` is a capped ring buffer.
public struct AttachSession: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case streaming, ended, failed(ErrorDetail) }
    public var phase: Phase
    public private(set) var lines: [LogLine]
    public let isReadOnly: Bool

    private let cap = 200

    public init(phase: Phase = .streaming, lines: [LogLine] = []) {
        self.phase = phase
        self.lines = lines
        self.isReadOnly = true
    }

    public mutating func append(_ line: LogLine) {
        lines.append(line)
        if lines.count > cap { lines.removeFirst(lines.count - cap) }
    }
}

/// The outcome of a start attempt. No `startedAttachmentFailed` — attach failure is a
/// separate channel (`AttachSession.phase`).
public enum ContainerStartResult: Sendable, Equatable {
    case started(attached: Bool)
    case createdButNotStarted
    case runFailed
    case failedBeforeExecution
    case backendUnavailable
    case interrupted

    public var operationStatus: OperationStatus {
        switch self {
        case .started: return .succeeded
        case .createdButNotStarted, .failedBeforeExecution: return .failedBeforeExecution
        case .runFailed: return .failedDuringExecution
        case .backendUnavailable: return .backendUnavailable
        case .interrupted: return .interruptedByUser
        }
    }
}

/// A user-facing lifecycle notice (non-fatal info or recoverable error).
public struct LifecycleNotice: Sendable, Equatable {
    public var detail: ErrorDetail
    public var offersShellHint: Bool

    public init(detail: ErrorDetail, offersShellHint: Bool = false) {
        self.detail = detail
        self.offersShellHint = offersShellHint
    }
}

/// The resolved outcome of a stop attempt.
public enum StopOutcome: Sendable, Equatable {
    case stopped
    case alreadyStopped
    case hung
    case failed(ErrorDetail)
}

/// Domain metrics for one container, mapped from a backend `ContainerStatsSample`. CPU% and
/// `capturedAt` are computed/stamped in the domain.
public struct ContainerMetrics: Sendable, Equatable, Identifiable {
    public var id: String
    public var cpuPercent: Double?
    public var memoryUsageBytes: UInt64?
    public var memoryLimitBytes: UInt64?
    public var networkRxBytes: UInt64?
    public var networkTxBytes: UInt64?
    public var blockReadBytes: UInt64?
    public var blockWriteBytes: UInt64?
    public var numProcesses: UInt64?
    public var capturedAt: Date

    public var memoryPercent: Double? {
        guard let used = memoryUsageBytes, let limit = memoryLimitBytes, limit > 0 else { return nil }
        return Double(used) / Double(limit) * 100
    }

    public init(sample: ContainerStatsSample, capturedAt: Date, cpuPercent: Double?) {
        self.id = sample.id
        self.cpuPercent = cpuPercent
        self.memoryUsageBytes = sample.memoryUsageBytes
        self.memoryLimitBytes = sample.memoryLimitBytes
        self.networkRxBytes = sample.networkRxBytes
        self.networkTxBytes = sample.networkTxBytes
        self.blockReadBytes = sample.blockReadBytes
        self.blockWriteBytes = sample.blockWriteBytes
        self.numProcesses = sample.numProcesses
        self.capturedAt = capturedAt
    }
}
```

- [ ] **Step 5: Run → pass** (`DomainModelTests`, `LifecycleTypesTests`).
- [ ] **Step 6: Commit** — `feat(domain): lifecycle value types + ContainerState.stopping`.

---

### Task 8: `ContainerStatsModel` (CPU% delta, epsilon guard, empty-ids no-op, clean interrupt)

**Files:**
- Create: `Sources/CapsuleDomain/ContainerStatsModel.swift`
- Test: `Tests/CapsuleUnitTests/ContainerStatsModelTests.swift`

**Interfaces — Produces:** `@MainActor @Observable ContainerStatsModel` with `metrics: [String: ContainerMetrics]`, `func snapshot(ids:) async`, `func startStreaming(ids:interval:)`, `func stop()`, internal CPU% from consecutive `cpuUsageUsec` deltas using `ContinuousClock` arrival stamps with an epsilon guard.

- [ ] **Step 1: Write failing tests:**

```swift
//
//  ContainerStatsModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class ContainerStatsModelTests: XCTestCase {
    func testSnapshotPopulatesMetrics() async {
        let backend = MockBackend(sampleStats: [
            ContainerStatsSample(id: "a1b2c3d4", cpuUsageUsec: 10, memoryUsageBytes: 5, memoryLimitBytes: 10)
        ])
        let model = ContainerStatsModel(backend: backend)
        await model.snapshot(ids: ["a1b2c3d4"])
        XCTAssertEqual(model.metrics["a1b2c3d4"]?.memoryPercent ?? -1, 50, accuracy: 0.001)
    }

    func testEmptyIdsDoesNotCallBackend() async {
        let backend = MockBackend()
        backend.failure = .nonZeroExit(command: "stats", code: 1, stderr: "should not be called")
        let model = ContainerStatsModel(backend: backend)
        await model.snapshot(ids: [])        // must early-return, not throw/populate
        XCTAssertTrue(model.metrics.isEmpty)
    }

    func testCPUPercentFromConsecutiveSamples() {
        let model = ContainerStatsModel(backend: MockBackend())
        // 1st sample at t=0: no prior → cpuPercent nil
        let m1 = model.ingestForTesting(
            ContainerStatsSample(id: "c", cpuUsageUsec: 0), atSeconds: 0)
        XCTAssertNil(m1.cpuPercent)
        // 2nd at t=1s: +1_000_000 usec over 1s = 100% (one core)
        let m2 = model.ingestForTesting(
            ContainerStatsSample(id: "c", cpuUsageUsec: 1_000_000), atSeconds: 1)
        XCTAssertEqual(m2.cpuPercent ?? -1, 100, accuracy: 0.5)
    }

    func testEpsilonGuardHoldsPriorCPUWhenElapsedTooSmall() {
        let model = ContainerStatsModel(backend: MockBackend())
        _ = model.ingestForTesting(ContainerStatsSample(id: "c", cpuUsageUsec: 0), atSeconds: 0)
        let m2 = model.ingestForTesting(ContainerStatsSample(id: "c", cpuUsageUsec: 1_000_000), atSeconds: 1)
        let m3 = model.ingestForTesting(
            ContainerStatsSample(id: "c", cpuUsageUsec: 2_000_000), atSeconds: 1)  // ~0 elapsed
        XCTAssertEqual(m3.cpuPercent, m2.cpuPercent)  // held, not divided by ~0
    }
}
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement:**

```swift
//
//  ContainerStatsModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. CPU% is computed
//  from consecutive cumulative samples; cadence/poll-loop live in the adapter's stream.

import CapsuleBackend
import Foundation
import Observation

@MainActor
@Observable
public final class ContainerStatsModel {
    public private(set) var metrics: [String: ContainerMetrics] = [:]
    public private(set) var isStreaming = false

    private let backend: any ContainerBackend
    private let now: () -> Date
    private var streamTask: Task<Void, Never>?
    private var priorCPU: [String: (usec: UInt64, at: Double)] = [:]  // at = seconds

    /// Minimum elapsed seconds before a CPU% delta is trusted.
    private let epsilon = 0.05

    public init(backend: any ContainerBackend, now: @escaping () -> Date = { Date() }) {
        self.backend = backend
        self.now = now
    }

    public func snapshot(ids: [String]) async {
        guard !ids.isEmpty else { return }
        guard let samples = try? await backend.containerStats(ids: ids) else { return }
        let at = monotonicSeconds()
        for sample in samples { metrics[sample.id] = compute(sample, at: at) }
    }

    public func startStreaming(ids: [String], interval: Duration = .seconds(2)) {
        stop()
        guard !ids.isEmpty else { return }
        isStreaming = true
        streamTask = Task { [weak self] in
            guard let stream = self?.backend.streamContainerStats(ids: ids, interval: interval)
            else { return }
            do {
                for try await batch in stream {
                    guard let self else { return }
                    let at = self.monotonicSeconds()
                    for sample in batch { self.metrics[sample.id] = self.compute(sample, at: at) }
                }
            } catch is CancellationError {
                // clean
            } catch {
                // streaming stats failure is non-fatal; stop quietly
            }
            self?.isStreaming = false
        }
    }

    /// Cancels streaming and restores cleanly (no leaked task/process).
    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    // MARK: CPU%

    private func compute(_ sample: ContainerStatsSample, at seconds: Double) -> ContainerMetrics {
        var cpuPercent: Double?
        if let usec = sample.cpuUsageUsec, let prior = priorCPU[sample.id] {
            let elapsed = seconds - prior.at
            if elapsed > epsilon, usec >= prior.usec {
                cpuPercent = Double(usec - prior.usec) / (elapsed * 1_000_000) * 100
            } else {
                cpuPercent = metrics[sample.id]?.cpuPercent  // hold prior value
            }
        }
        if let usec = sample.cpuUsageUsec {
            // Only advance the baseline when the elapsed window was meaningful, so a
            // burst of near-simultaneous samples doesn't poison the next delta.
            if priorCPU[sample.id] == nil || seconds - (priorCPU[sample.id]?.at ?? 0) > epsilon {
                priorCPU[sample.id] = (usec, seconds)
            }
        }
        return ContainerMetrics(sample: sample, capturedAt: now(), cpuPercent: cpuPercent)
    }

    private func monotonicSeconds() -> Double {
        // ContinuousClock-based monotonic seconds; injected `now()` covers wall-clock stamp.
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    #if DEBUG
    /// Test seam: ingest a sample at a synthetic monotonic time (seconds) and return the metric.
    func ingestForTesting(_ sample: ContainerStatsSample, atSeconds: Double) -> ContainerMetrics {
        let m = compute(sample, at: atSeconds)
        metrics[sample.id] = m
        return m
    }
    #endif
}
```

(If `#if DEBUG` test seams are discouraged in this codebase, instead make `compute` `internal` and inject the monotonic clock; the tests call `compute` directly. Match the codebase's preference — `@testable import` already gives access to `internal`.)

- [ ] **Step 4: Run → pass.**
- [ ] **Step 5: Commit** — `feat(domain): ContainerStatsModel with CPU% delta + epsilon guard + clean interrupt`.

---

### Task 9: `ContainerLifecycleModel` — start + settle-window classify + attach

**Files:**
- Create: `Sources/CapsuleDomain/ContainerLifecycleModel.swift`
- Test: `Tests/CapsuleUnitTests/ContainerLifecycleModelTests.swift`

**Interfaces — Produces (start/attach portion):** `@MainActor @Observable ContainerLifecycleModel` with injected seams `normalize`, `onActivity`, `reloadList: () async -> Void`, `currentState: (String) -> ContainerState`, `terminalAvailable: () -> Bool`, `copyCommand: ([String]) -> Void`, and a `settleAttempts`/`settleDelay` for deterministic tests. `func start(id:attach:) async -> ContainerStartResult`; `attachSession`, `busy: Set<String>`, `notice: LifecycleNotice?`.

- [ ] **Step 1: Write failing tests (start/attach):**

```swift
//
//  ContainerLifecycleModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class ContainerLifecycleModelTests: XCTestCase {
    private func model(
        backend: any ContainerBackend = MockBackend(),
        state: @escaping (String) -> ContainerState = { _ in .running }
    ) -> ContainerLifecycleModel {
        ContainerLifecycleModel(
            backend: backend, currentState: state, settleAttempts: 2, settleDelay: .zero)
    }

    func testStartSucceedsWhenContainerEndsRunning() async {
        let m = model(state: { _ in .running })
        let result = await m.start(id: "e5f6a7b8", attach: false)
        XCTAssertEqual(result, .started(attached: false))
    }

    func testStartRunFailedWhenStillNotRunningAfterSettle() async {
        let m = model(state: { _ in .stopped })
        let result = await m.start(id: "e5f6a7b8", attach: false)
        XCTAssertEqual(result, .runFailed)
    }

    func testStartThrowingBecomesCreatedButNotStarted() async {
        let backend = MockBackend()
        backend.failure = .nonZeroExit(command: "start", code: 1, stderr: "boom")
        let m = model(backend: backend, state: { _ in .stopped })
        let result = await m.start(id: "e5f6a7b8", attach: false)
        XCTAssertEqual(result, .createdButNotStarted)
    }

    func testStartBackendUnavailableClassified() async {
        let backend = MockBackend()
        backend.failure = .executableNotFound("container")
        let m = model(backend: backend)
        XCTAssertEqual(await m.start(id: "x", attach: false), .backendUnavailable)
    }
}
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement the model (start/attach first; stop added in Task 10).** Create `ContainerLifecycleModel.swift`:

```swift
//
//  ContainerLifecycleModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Owns the
//  non-destructive lifecycle actions; ContainerBrowserModel stays a pure read surface.

import CapsuleBackend
import Foundation
import Observation

@MainActor
@Observable
public final class ContainerLifecycleModel {
    public private(set) var busy: Set<String> = []
    public private(set) var attachSession: AttachSession?
    public var notice: LifecycleNotice?

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void
    private let reloadList: @MainActor () async -> Void
    private let currentState: @MainActor (String) -> ContainerState
    private let terminalAvailable: @MainActor () -> Bool
    private let copyCommand: @MainActor ([String]) -> Void
    private let settleAttempts: Int
    private let settleDelay: Duration

    private var attachTask: Task<Void, Never>?
    private var nextLogLineID = 0

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel.defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in },
        reloadList: @escaping @MainActor () async -> Void = {},
        currentState: @escaping @MainActor (String) -> ContainerState = { _ in .unknown },
        terminalAvailable: @escaping @MainActor () -> Bool = { false },
        copyCommand: @escaping @MainActor ([String]) -> Void = { _ in },
        settleAttempts: Int = 4,
        settleDelay: Duration = .milliseconds(400)
    ) {
        self.backend = backend
        self.normalize = normalize
        self.onActivity = onActivity
        self.reloadList = reloadList
        self.currentState = currentState
        self.terminalAvailable = terminalAvailable
        self.copyCommand = copyCommand
        self.settleAttempts = settleAttempts
        self.settleDelay = settleDelay
    }

    // MARK: Start

    public func start(id: String, attach: Bool) async -> ContainerStartResult {
        busy.insert(id)
        defer { busy.remove(id) }
        do {
            try await backend.startContainer(id: id)
        } catch {
            let capsule = normalize(error)
            switch capsule.status {
            case .backendUnavailable:
                onActivity("Start failed — container service unavailable.")
                notice = LifecycleNotice(detail: capsule.detail)
                return .backendUnavailable
            case .failedBeforeExecution:
                notice = LifecycleNotice(detail: capsule.detail)
                return .failedBeforeExecution
            default:
                // The container resource pre-exists for `start`, so a failure here is
                // "created but not started", not "run failed".
                onActivity("“\(id)” created but not started.")
                notice = LifecycleNotice(detail: capsule.detail)
                return .createdButNotStarted
            }
        }

        // Provisional success → verify over a bounded settle window (best-effort).
        var running = false
        for _ in 0..<max(1, settleAttempts) {
            await reloadList()
            if currentState(id) == .running { running = true; break }
            if settleDelay > .zero { try? await Task.sleep(for: settleDelay) }
        }
        guard running else {
            onActivity("“\(id)” failed to run.")
            notice = LifecycleNotice(detail: CapsuleError.commandFailed(
                command: ["container", "start", id], exitCode: nil,
                stderr: "Container did not reach the running state.").detail)
            return .runFailed
        }

        onActivity("Started “\(id)”.")
        if attach { beginAttach(id: id) }
        return .started(attached: attach)
    }

    /// Sequential, continue-on-failure bulk start; attach disabled for multi-select.
    public func startAll(ids: [String]) async {
        var ok = 0
        for id in ids where currentState(id) != .running {
            if case .started = await start(id: id, attach: false) { ok += 1 }
        }
        onActivity("Started \(ok) of \(ids.count) container(s).")
    }

    // MARK: Attach (read-only interim)

    public func beginAttach(id: String) {
        attachTask?.cancel()
        attachSession = AttachSession(phase: .streaming)
        attachTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await line in self.backend.followLogs(container: id) {
                    self.appendAttachLine(line)
                }
                self.attachSession?.phase = .ended
            } catch is CancellationError {
                // clean teardown
            } catch {
                self.attachSession?.phase = .failed(self.normalize(error).detail)
                self.notice = LifecycleNotice(
                    detail: ErrorDetail(
                        title: "Started, but couldn't attach",
                        explanation: self.normalize(error).detail.explanation,
                        recoveryActions: [.retry]),
                    offersShellHint: true)
            }
        }
    }

    public func retryAttach(id: String) { beginAttach(id: id) }

    public func detach() {
        attachTask?.cancel()
        attachTask = nil
        attachSession = nil
    }

    private func appendAttachLine(_ line: OutputLine) {
        nextLogLineID += 1
        attachSession?.append(LogLine(id: nextLogLineID, source: line.source, text: line.text))
    }
}
```

- [ ] **Step 4: Run → pass** (start tests). Add attach tests next:

```swift
    func testAttachSingleFlightAndRingBuffer() async {
        let backend = MockBackend(logLines: (0..<300).map { OutputLine(source: .stdout, text: "\($0)") })
        let m = model(backend: backend, state: { _ in .running })
        _ = await m.start(id: "e5f6a7b8", attach: true)
        // allow the attach pump to drain the seeded stream
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(m.attachSession?.lines.count, 200)
        m.detach()
        XCTAssertNil(m.attachSession)
    }
```

Run → pass (adjust the sleep if flaky; the MockBackend stream yields synchronously then finishes).

- [ ] **Step 5: Commit** — `feat(domain): ContainerLifecycleModel start + settle-window classify + read-only attach`.

---

### Task 10: `ContainerLifecycleModel` — stop + hang detection + hybrid interim Force Stop

**Files:**
- Modify: `Sources/CapsuleDomain/ContainerLifecycleModel.swift`
- Test: `Tests/CapsuleUnitTests/ContainerLifecycleModelTests.swift`

**Interfaces — Produces:** `func stop(id:options:) async -> StopOutcome`; `func forceStop(id:) async` (interim, `.forced`); hang watchdog with injected `hangTimeout`; per-container `stopState`; "already stopped" benign interception before normalization; retry-in-terminal copies `["container","kill",id]`.

- [ ] **Step 1: Write failing tests:**

```swift
    func testStopMarksStopped() async {
        let backend = MockBackend()
        let m = model(backend: backend, state: { _ in .stopped })
        let outcome = await m.stop(id: "a1b2c3d4", options: .default)
        XCTAssertEqual(outcome, .stopped)
        XCTAssertEqual(backend.lastStopOptions, .default)
    }

    func testStopAlreadyStoppedIsBenignNotDaemonError() async {
        let backend = MockBackend()
        backend.failure = .nonZeroExit(
            command: "stop", code: 1,
            stderr: #"internalError: "failed to stop container" (cause: "invalidState: container is not running")"#)
        let m = model(backend: backend, state: { _ in .stopped })
        let outcome = await m.stop(id: "a1b2c3d4", options: .default)
        XCTAssertEqual(outcome, .alreadyStopped)   // not .failed, not daemonUnavailable
    }

    func testForceStopIssuesForcedOptions() async {
        let backend = MockBackend()
        let m = model(backend: backend, state: { _ in .stopped })
        await m.forceStop(id: "a1b2c3d4")
        XCTAssertEqual(backend.lastStopOptions, .forced)
    }
```

(Hang detection itself is timing-based; assert the state-machine transition with an injected tiny `hangTimeout` + a backend whose stop never returns — use a `MockBackend` subclass/flag that suspends. If that is heavy, assert the simpler invariant: a successful stop never enters `.hung`. Keep the hang path covered by at least the `forceStop` issuing `.forced`.)

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement.** Add to `ContainerLifecycleModel` an injected `hangTimeout: Duration` (default `.seconds(8)`; tests pass `.zero`/tiny), a `stopState: [String: StopPhase]` if needed, and:

```swift
    public func stop(id: String, options: StopOptions) async -> StopOutcome {
        busy.insert(id)
        defer { busy.remove(id) }
        do {
            try await backend.stopContainer(id: id, options: options)
            await reloadList()
            onActivity("Stopped “\(id)”.")
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

    /// Interim Force Stop (hybrid): immediate force through the non-destructive stop verb.
    public func forceStop(id: String) async {
        _ = await stop(id: id, options: .forced)
    }

    /// Builds the hang notice (5B: working Force Stop via `.forced` + copy `container kill`).
    public func makeHangNotice(id: String) -> LifecycleNotice {
        LifecycleNotice(detail: ErrorDetail(
            title: "Stop is taking longer than expected",
            explanation: "You can force the container to stop now, or copy the kill command.",
            recoveryActions: [.retry, .retryInTerminal(command: ["container", "kill", id])]))
    }

    /// Container-level "already stopped / not running" is benign and must not be normalized
    /// into a daemon-unavailable error (ErrorNormalizer's daemonSignatures include "not
    /// running"). Intercept the raw BackendError first.
    private func isBenignAlreadyStopped(_ error: any Error) -> Bool {
        guard case let BackendError.nonZeroExit(_, _, stderr) = error else { return false }
        let s = stderr.lowercased()
        let benign = s.contains("not running") || s.contains("already stopped")
            || s.contains("invalidstate") || s.contains("invalid state")
        let daemon = s.contains("xpc") || s.contains("launchd") || s.contains("connection refused")
        return benign && !daemon
    }
```

The watchdog (hang detection) wraps the `stop` call: race `Task { try await backend.stopContainer(...) }` against `Task { try await Task.sleep(for: hangTimeout) }`. On timeout-first, set `notice = makeHangNotice(id:)` and return `.hung` (the original stop continues in the background; it is idempotent). Implement with a `withTaskGroup` or a simple `Task.select`-style race; keep the success path returning `.stopped`. Where `hangTimeout == .zero` is injected, treat as "no watchdog" to keep deterministic tests simple, OR add a dedicated `MockBackend` suspend flag for the hang test.

- [ ] **Step 4: Run → pass.**
- [ ] **Step 5: Commit** — `feat(domain): stop + hang detection + hybrid interim Force Stop`.

---

### Task 11: UI — stat chips, stats pane, attach console, sheets, notice view

**Files:**
- Create: `Sources/CapsuleUI/StatChips.swift`, `StatsPaneView.swift`, `AttachConsoleView.swift`, `StartAttachSheet.swift`, `StopOptionsSheet.swift`, `LifecycleNoticeView.swift`

**Interfaces:** SwiftUI views binding only to domain types (`ContainerMetrics`, `AttachSession`, `LifecycleNotice`, `ContainerLifecycleModel`, `ContainerStatsModel`). Verified by build + inspection.

- [ ] **Step 1: Implement each view** with complete code (formatting helpers inline; use `ByteCountFormatStyle` for bytes, `%.1f%%` for CPU). Key requirements:
  - `StatChips(metrics: ContainerMetrics?)` — compact CPU/mem chips for a Table row; renders "—" when nil.
  - `StatsPaneView(metrics: ContainerMetrics?, isStreaming: Bool, onToggleLive: ...)` — labeled CPU/mem/net/io/pids + a live/snapshot toggle; notes the ~2 s cadence.
  - `AttachConsoleView(session: AttachSession, onDetach:, onRetry:, terminalAvailable: Bool)` — monospaced lines (`.error` colored as CLI-diagnostic), a **read-only badge**, Detach, a **disabled** "Open Shell" captioned for M6, and a `.streaming/.ended/.failed` footer.
  - `StartAttachSheet(onStart: (_ attach: Bool) -> Void)` — explains the read-only attach interim + disabled exec-shell.
  - `StopOptionsSheet(onStop: (StopOptions) -> Void)` — timeout stepper (default 5) + graceful signal picker (TERM/INT), maps to `StopOptions`.
  - `LifecycleNoticeView(notice: LifecycleNotice, onRetry:, onRetryInTerminal:, onOpenLogs:)` — renders `ErrorDetail` + buttons; `.retry` is **container-scoped** (caller supplies the closure; never `systemModel.refreshStatus()`).
- [ ] **Step 2: `make build`** → compiles, zero warnings.
- [ ] **Step 3: Commit** — `feat(ui): lifecycle views (chips, stats pane, attach console, sheets, notice)`.

---

### Task 12: UI wiring — list toolbar/menu, inspector chips/pane, activity attach console

**Files:**
- Modify: `Sources/CapsuleUI/ContainerListView.swift`, `ContainerInspectorView.swift`, `ActivityPaneView.swift`, `ContentColumnView.swift`, `AppShellView.swift`, `RootView.swift`

**Interfaces:** thread `ContainerLifecycleModel` + `ContainerStatsModel` through the shell; add Start/Stop affordances + sheets; render stat chips/pane + attach console.

- [ ] **Step 1: Implement.**
  - `ContainerListView`: Start/Stop toolbar buttons + `contextMenu(forSelectionType: Container.ID.self)` with Start, "Start and Attach…", Stop, "Stop…", per-row busy spinner (when `lifecycle.busy.contains(id)`); present `StartAttachSheet`/`StopOptionsSheet`; a `StatChips` column when stats are present. Disable Start for running, Stop for stopped.
  - `ContainerInspectorView`: in Summary, add `StatsPaneView` + a live/snapshot toggle that calls `statsModel.startStreaming(ids:)`/`snapshot(ids:)`/`stop()` for the selected running container; `.task(id: selection)` starts/stops streaming and **early-returns for empty/non-running**; tears down on disappear.
  - `ActivityPaneView`: when `lifecycle.attachSession != nil`, render `AttachConsoleView`.
  - `ContentColumnView`/`AppShellView`/`RootView`: add `lifecycleModel`/`statsModel` params and thread them (mirror the 5A `browserModel` threading).
- [ ] **Step 2: `make build`** → compiles, zero warnings (call sites updated in Task 13).
- [ ] **Step 3: Commit (with Task 13)** — interdependent call sites; commit together.

---

### Task 13: Composition root — construct & wire both models

**Files:**
- Modify: `Sources/CapsuleApp/AppEnvironment.swift`, `Sources/CapsuleApp/CapsuleScene.swift`
- Test: `Tests/CapsuleUnitTests/CompositionTests.swift`

**Interfaces:** `AppEnvironment` gains `lifecycleModel`, `statsModel`; `live()` constructs them with seams: `normalize: ErrorNormalizer.normalize`, `onActivity: shell.appendActivity`, `reloadList: { await browserModel.refresh() }`, `currentState: { browserModel.allContainers.first{$0.id==$0}... }`, `terminalAvailable: { false }`, `copyCommand:` a **clipboard** closure (join argv, `NSPasteboard`) + activity note.

- [ ] **Step 1: Write the failing composition test:**

```swift
    @MainActor
    func testLiveEnvironmentBuildsLifecycleAndStatsModels() {
        let env = AppEnvironment.live()
        XCTAssertTrue(env.lifecycleModel.busy.isEmpty)
        XCTAssertNil(env.lifecycleModel.attachSession)
        XCTAssertTrue(env.statsModel.metrics.isEmpty)
    }
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement.** Add the properties + init params to `AppEnvironment`; in `live()`:

```swift
        let statsModel = ContainerStatsModel(backend: backend)
        let lifecycleModel = ContainerLifecycleModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            reloadList: { await browserModel.refresh() },
            currentState: { id in browserModel.allContainers.first { $0.id == id }?.state ?? .unknown },
            terminalAvailable: { false },
            copyCommand: { argv in
                let command = argv.joined(separator: " ")
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(command, forType: .string)
                shell.appendActivity("Copied to clipboard: \(command)")
            }
        )
```

Thread both into `AppEnvironment(...)`, `CapsuleScene` (`@State`), `RootView`, `AppShellView`. (`AppEnvironment` may `import AppKit` for `NSPasteboard`.)

- [ ] **Step 4: `make build` + run `CompositionTests`** → pass.
- [ ] **Step 5: Commit (Tasks 12 + 13)** — `feat(app): wire lifecycle + stats models into the shell`.

---

### Task 14: Full verification + adversarial review

**Files:** none (verification).

- [ ] **Step 1: `make ci`** → green (zero-warning build, swift-format --strict, arch guard, headers, all tests). If format flags, `make format` then re-run.
- [ ] **Step 2: `make app`** → builds; launch and smoke-check against the live service: Containers list shows Start/Stop affordances; selecting a running container shows stat chips/pane (0 containers locally → empty/“—”, but the path runs); daemon-down still shows health, not empty. Visual pass by inspection.
- [ ] **Step 3 (ultracode): adversarial review.** Run a review workflow over the 5B diff (dimensions: arch-guard, concurrency/cancellation leaks, error-classification correctness, CLI-argv fidelity, test coverage of must-fixes) and apply confirmed fixes.
- [ ] **Step 4: Commit** any format/review fixes.

---

## Self-Review

**Spec coverage:** start (+attach interim) → Tasks 9, 11, 12; created-vs-run-failed → Task 9 (settle window); stop + timeout/signal → Tasks 2,3,5,10; hang detection + hybrid interim Force Stop → Task 10; stats live+chips+snapshot → Tasks 2,4,5,8,11,12; retry-in-terminal clipboard interim → Task 13; daemon-down unchanged (5A gate). ✔

**Must-fix coverage:** (1) explicit running ids → Task 8/12; (2) prune stdout+stderr → 5C (noted); (3) stream lifecycle → Tasks 2,5,8; (4) created-vs-runFailed settle window → Task 9; (5) CPU% epsilon → Task 8; (6) remove arity-1 stop → Tasks 2,5; (7) `--no-stream` redundant (noted, included) → Task 3; (8) single attach-failure channel → Task 9; (9) attach single-flight + teardown + ring buffer → Tasks 7,9; (10) dedicated AttachConsoleView → Task 11; (11) honest stream labeling → Task 7; (12) Retry Attach not Open Logs → Task 9; (13) runFailed best-effort settle → Task 9; (14) OperationStatus via resolve — *simplified*: `ContainerStartResult.operationStatus` maps directly (documented), since `resolve` adds no signal here; (15) bulk start sequential continue-on-failure → Task 9; (16) container-scoped notice retry → Tasks 10,11; (17) `ContainerState.stopping` → Task 7. Plus CLIProcessRunner cancellation → Task 6; ErrorNormalizer "not running" collision intercepted in-domain → Task 10. ✔

**Placeholder scan:** every code step shows real code; the few "match the file's API" notes (ArgumentBuilder/flag) are explicit adaptation instructions, not placeholders — the implementer reads the small file and mirrors it. ✔

**Type consistency:** `StopOptions`/`ContainerStatsSample` (Backend) → `ContainerMetrics`/`LogLine`/`AttachSession`/`ContainerStartResult`/`StopOutcome` (Domain) used consistently across Tasks 7–13; model method names (`start`,`startAll`,`beginAttach`,`detach`,`retryAttach`,`stop`,`forceStop`,`snapshot`,`startStreaming`,`stop()`) stable. No Backend type appears in a UI view signature (UI binds to the domain models + `ContainerMetrics`/`AttachSession`). ✔

**Note on Tasks 12+13:** interdependent (view params ↔ call sites); built and committed together (Task 13 Step 4–5), the one place a task doesn't end green in isolation — by design.
