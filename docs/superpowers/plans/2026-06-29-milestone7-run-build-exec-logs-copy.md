# Milestone 7 · Run / Build / Exec / Logs / Copy + terminal + Activity pane — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the core GUI workflows (run, build, exec, logs, copy) on top of the integrated terminal and finish the Activity-pane task model (queue, progress, transcript, cancel, retry for every long job).

**Architecture:** Ports & Adapters. New value types + port methods in `CapsuleBackend`; `@Observable` models in `CapsuleDomain`; SwiftUI sheets/views in `CapsuleUI`; CLI argv in `CapsuleCLIBackend`; wiring in `CapsuleApp`. Interactive run/exec/machine-shell go through the existing `TerminalRequest` + `TerminalSurfaceProviding` (PTY) seam; detached run, build, copy, logs-fetch, and `ls`-listing go through the `ContainerBackend` port. `RunConfiguration`/`BuildConfiguration` own a computed `arguments` argv consumed by BOTH the CLI adapter and the Domain terminal-request builder.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, SwiftTerm (already integrated), XcodeGen.

## Global Constraints

- Build CLI tests with **`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`** (XCTest needs Xcode; CLT-only `swift build` compiles but cannot test).
- Arch-guard invariants (enforced by `ArchitectureGuardTests` + `Scripts/check-architecture.sh`): **UI imports no Backend module**; **Domain imports no UI and no `Foundation.Process`**. No backend type may appear in any UI signature.
- License header on every new file (pre-commit hook enforces it — copy the header block from any existing file in the same module).
- Secrets never on argv (carried from M6); not directly relevant to M7 but keep the invariant.
- `swift-format` clean (`make format` then `make lint`); commit small and often (one task = one commit).
- Verify before claiming done: run the full suite + arch + lint, then a live GUI smoke, exactly as M5/M6.
- The CLI subcommand for copy is **`copy`** (not the `cp` alias). Build's default `--tag` is a random UUID, so a tag is **required** in the UI.

---

## Phase 1 — Activity task model (foundation: cancel, progress, new kinds)

### Task 1.1: `TaskState.cancelled`

**Files:**
- Modify: `Sources/CapsuleDomain/TaskState.swift`
- Test: `Tests/CapsuleUnitTests/OperationStatusTests.swift` (or `TaskCenterTests.swift` — add a `TaskState` case test there)

**Interfaces:**
- Produces: `TaskState.cancelled` with `isActive == false`.

- [ ] **Step 1: Failing test** — in `TaskCenterTests.swift` add:
```swift
func testCancelledStateIsNotActive() {
    XCTAssertFalse(TaskState.cancelled.isActive)
    XCTAssertTrue(TaskState.running(progress: nil).isActive)
}
```
- [ ] **Step 2: Run** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter TaskCenterTests/testCancelledStateIsNotActive` → FAIL (no `.cancelled`).
- [ ] **Step 3: Implement** — add `case cancelled` to `TaskState`; in `isActive`, group `cancelled` with the non-active cases (`case .idle, .succeeded, .failed, .cancelled: return false`).
- [ ] **Step 4: Run** the filter → PASS. Then full `swift test` to catch any non-exhaustive `switch` on `TaskState` (fix each: `TaskTranscriptView.stateIcon`, anywhere matching `.failed`).
- [ ] **Step 5: Commit** `feat(tasks): add neutral .cancelled task state`.

### Task 1.2: Expand `OperationKind` (build/run/export/systemStart/copy)

**Files:**
- Modify: `Sources/CapsuleDomain/TaskCenter.swift`
- Test: `Tests/CapsuleUnitTests/TaskCenterTests.swift`

**Interfaces:**
- Produces: `OperationKind` cases `.build, .run, .export, .systemStart, .copy` each with `title` + `symbolName`.

- [ ] **Step 1: Failing test**:
```swift
func testNewOperationKindsHaveTitlesAndSymbols() {
    for kind in [OperationKind.build, .run, .export, .systemStart, .copy] {
        XCTAssertFalse(kind.title.isEmpty)
        XCTAssertFalse(kind.symbolName.isEmpty)
    }
    XCTAssertEqual(OperationKind.build.title, "Build")
    XCTAssertEqual(OperationKind.run.title, "Run")
}
```
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — add the cases + `title`/`symbolName` arms: build→"Build"/"hammer", run→"Run"/"play.rectangle", export→"Export"/"square.and.arrow.up.on.square", systemStart→"Start Services"/"power", copy→"Copy"/"doc.on.doc".
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(tasks): add build/run/export/systemStart/copy operation kinds`.

### Task 1.3: `ProgressParser` (determinate progress from a clean `NN%`)

**Files:**
- Create: `Sources/CapsuleDomain/ProgressParser.swift`
- Test: `Tests/CapsuleUnitTests/ProgressParserTests.swift`

**Interfaces:**
- Produces: `enum ProgressParser { static func fraction(in line: String) -> Double? }` returning `0.0...1.0` or `nil`.

- [ ] **Step 1: Failing test**:
```swift
func testParsesCleanPercent() {
    XCTAssertEqual(ProgressParser.fraction(in: "Downloading 42%"), 0.42, accuracy: 0.001)
    XCTAssertEqual(ProgressParser.fraction(in: "[100%] done"), 1.0, accuracy: 0.001)
}
func testIgnoresLinesWithoutPercent() {
    XCTAssertNil(ProgressParser.fraction(in: "Step 2/5 : RUN echo hi"))
    XCTAssertNil(ProgressParser.fraction(in: "pulling layer sha256:abc"))
}
func testClampsAndTakesLastPercent() {
    XCTAssertEqual(ProgressParser.fraction(in: "a 10% b 80%"), 0.80, accuracy: 0.001)
}
```
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — regex `([0-9]{1,3})%`, take the last match, clamp to `0...100`, divide by 100. No match → nil. Pure, no Foundation.Process.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(tasks): ProgressParser for determinate progress from CLI percent lines`.

### Task 1.4: `TaskCenter.cancel` + progress wiring + cancellable flag

**Files:**
- Modify: `Sources/CapsuleDomain/TaskCenter.swift`
- Test: `Tests/CapsuleUnitTests/TaskCenterTests.swift`

**Interfaces:**
- Consumes: `ProgressParser.fraction(in:)`.
- Produces: `TaskCenter.cancel(_ task: OperationTask)`; `OperationTask.isCancellable: Bool`; streaming driver updates `state = .running(progress:)` from parsed lines; `CancellationError` → `.cancelled`.

- [ ] **Step 1: Failing tests**:
```swift
func testCancelStopsRunningTaskAndMarksCancelled() async {
    let center = TaskCenter()
    let gate = AsyncStream<OutputLine>.makeStream()   // never finishes until we cancel
    let task = center.runStreaming(kind: .build, title: "build") {
        AsyncThrowingStream { cont in
            let t = Task { for await l in gate.stream { cont.yield(l) }; cont.finish() }
            cont.onTermination = { _ in t.cancel() }
        }
    }
    await Task.yield()
    center.cancel(task)
    await task.wait()
    XCTAssertEqual(task.state, .cancelled)
    XCTAssertFalse(task.state.isActive)
}
func testStreamingUpdatesDeterminateProgress() async {
    let center = TaskCenter()
    let task = center.runStreaming(kind: .pull, title: "pull") {
        AsyncThrowingStream { cont in
            cont.yield(OutputLine(source: .stdout, text: "Downloading 50%"))
            cont.finish()
        }
    }
    await task.wait()
    // last running progress observed was 0.5 before success; assert transcript captured the line
    XCTAssertTrue(task.transcriptText.contains("50%"))
}
func testRetryOfCancelledReRuns() async {
    // cancel then retry drives again and can succeed
}
```
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement**:
  - Add `public internal(set) var isCancellable: Bool = true` to `OperationTask`.
  - In `drive(_:)` streaming + async branches, wrap the body so a thrown `CancellationError` (or `task.driver?.isCancelled`) sets `task.state = .cancelled` instead of `recordFailure`.
  - In the streaming loop, after `task.append(...)`, call `if let f = ProgressParser.fraction(in: line.text) { task.state = .running(progress: f) }`.
  - Add `public func cancel(_ task: OperationTask) { guard task.state.isActive else { return }; task.driver?.cancel() }`. (Driver's `catch is CancellationError` sets `.cancelled`; for the non-streaming `runAsync` branch, `CLIProcessRunner` cancellation terminates the child and surfaces as an error/cancellation — catch `CancellationError` first.)
- [ ] **Step 4: Run** the three tests + full `TaskCenterTests` → PASS.
- [ ] **Step 5: Commit** `feat(tasks): cancel + determinate-progress wiring in TaskCenter`.

### Task 1.5: UI — cancel button + progress bar in tasks/progress tabs

**Files:**
- Modify: `Sources/CapsuleUI/TaskTranscriptView.swift`, `Sources/CapsuleUI/ActivityPaneView.swift`
- Test: none new (SwiftUI views); covered by build/run later + manual smoke. (Keep `BannerPresentationTests` style if a pure helper is extracted.)

**Interfaces:**
- Consumes: `OperationTask.state`, `OperationTask.isCancellable`, `TaskCenter.cancel`.

- [ ] **Step 1:** Add `var onCancel: (() -> Void)?` to `TaskTranscriptView`; show a Stop button while `task.state.isActive && task.isCancellable`; add a `.cancelled` arm to `stateIcon` (gray `minus.circle.fill` or `stop.circle`); render a determinate `ProgressView(value:)` when `state == .running(progress:)` with non-nil progress, else the existing indeterminate spinner.
- [ ] **Step 2:** In `ActivityPaneView.tasksList`, pass `onCancel: { taskCenter?.cancel(task) }`; in `progressList`, render `ProgressView(value:)` when determinate and a Stop button.
- [ ] **Step 3:** `swift build` (CLT) compiles; `make format`/`make lint` clean.
- [ ] **Step 4: Commit** `feat(ui): cancel button + determinate progress in Activity pane`.

### Task 1.6: Route export + system-start through the TaskCenter

**Files:**
- Modify: `Sources/CapsuleDomain/ContainerLifecycleModel.swift` (export), `Sources/CapsuleDomain/SystemStatusModel.swift` (startServices)
- Test: `Tests/CapsuleUnitTests/ContainerLifecycleModelTests.swift`, `Tests/CapsuleUnitTests/SystemStatusModelTests.swift`

**Interfaces:**
- Consumes: a `taskCenter` injected into both models (new optional init param, default nil to keep existing tests compiling).
- Produces: `export(id:to:)` registers a `.export` `runAsync` task; `startServices()` registers a `.systemStart` task.

- [ ] **Step 1: Failing test** (lifecycle): inject a `TaskCenter`, call `export`, assert `taskCenter.tasks` gains one `.export` task that succeeds (Mock export succeeds).
```swift
func testExportRegistersTask() async {
    let center = TaskCenter()
    let model = ContainerLifecycleModel(backend: MockBackend(), taskCenter: center)
    await model.export(id: "c1", to: URL(fileURLWithPath: "/tmp/x.tar"))
    XCTAssertEqual(center.tasks.count, 1)
    XCTAssertEqual(center.tasks.first?.kind, .export)
}
```
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — add `taskCenter: TaskCenter? = nil` param; in `export`, if a center is present, `center.runAsync(kind: .export, title: "Export \(id)") { try await backend.exportContainer(id: id, to: url) }` and return; keep the notice path only as a fallback when no center. Same shape for `startServices` (`.systemStart`, title "Start services"). Keep the settle/refresh behavior after success via `onSuccess`.
- [ ] **Step 4: Run** both suites → PASS.
- [ ] **Step 5: Commit** `feat(tasks): export + system-start register Activity tasks`.

---

## Phase 2 — Backend: value types, port, CLI adapter, mock

### Task 2.1: `RunConfiguration` + `arguments`

**Files:**
- Create: `Sources/CapsuleBackend/RunConfiguration.swift`
- Test: `Tests/CapsuleUnitTests/RunConfigurationTests.swift`

**Interfaces:**
- Produces: `struct RunConfiguration` (fields per design §3.1) with `var arguments: [String]`.

- [ ] **Step 1: Failing tests** (exact argv):
```swift
func testDetachedRunArgv() {
    let c = RunConfiguration(image: "nginx:latest", name: "web", command: [],
        env: ["FOO=bar"], publishPorts: ["8080:80"], volumes: ["/h:/c"],
        workdir: "/app", user: nil, interactive: false, tty: false, detach: true, remove: true)
    XCTAssertEqual(c.arguments,
        ["run", "-d", "--rm", "--name", "web", "-e", "FOO=bar",
         "-p", "8080:80", "-v", "/h:/c", "-w", "/app", "nginx:latest"])
}
func testInteractiveRunArgvWithCommand() {
    let c = RunConfiguration(image: "alpine", name: nil, command: ["sh", "-c", "echo hi"],
        env: [], publishPorts: [], volumes: [], workdir: nil, user: nil,
        interactive: true, tty: true, detach: false, remove: false)
    XCTAssertEqual(c.arguments, ["run", "-i", "-t", "alpine", "sh", "-c", "echo hi"])
}
```
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `arguments`: start `["run"]`; append `-d` if detach; `-i` if interactive; `-t` if tty; `--rm` if remove; `--name name`; each env as `-e v`; each port as `-p v`; each volume as `-v v`; `-w workdir`; `-u user`; then `image`; then `command…`. (Order: flags, then image, then command — image must precede init args.)
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(backend): RunConfiguration with argv builder`.

### Task 2.2: `BuildConfiguration` + `arguments`

**Files:**
- Create: `Sources/CapsuleBackend/BuildConfiguration.swift`
- Test: `Tests/CapsuleUnitTests/BuildConfigurationTests.swift`

- [ ] **Step 1: Failing tests**:
```swift
func testBuildArgvDefaults() {
    let c = BuildConfiguration(contextDirectory: URL(fileURLWithPath: "/proj"),
        tag: "app:dev", dockerfile: nil, buildArgs: [], noCache: false, plainProgress: false)
    XCTAssertEqual(c.arguments, ["build", "--tag", "app:dev", "/proj"])
}
func testBuildArgvFull() {
    let c = BuildConfiguration(contextDirectory: URL(fileURLWithPath: "/proj"),
        tag: "app:dev", dockerfile: "docker/Dockerfile", buildArgs: ["VER=1"],
        noCache: true, plainProgress: true)
    XCTAssertEqual(c.arguments,
        ["build", "--tag", "app:dev", "--file", "docker/Dockerfile",
         "--build-arg", "VER=1", "--no-cache", "--progress", "plain", "/proj"])
}
```
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `arguments`: `["build", "--tag", tag]`; `--file dockerfile`; each build-arg as `--build-arg v`; `--no-cache` if set; `--progress plain` if plainProgress; then `contextDirectory.path`.
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** `feat(backend): BuildConfiguration with argv builder`.

### Task 2.3: `ContainerFileEntry` value type

**Files:**
- Create: `Sources/CapsuleBackend/ContainerFileEntry.swift`
- Test: folded into Task 2.7 (parsing).

- [ ] **Step 1:** Implement `struct ContainerFileEntry: Sendable, Equatable, Identifiable { let name; let isDirectory; let size: Int64?; let mode: String?; var id: String { name } }`. **Commit** with Task 2.7.

### Task 2.4: Port additions on `ContainerBackend`

**Files:**
- Modify: `Sources/CapsuleBackend/ContainerBackend.swift`
- Test: compile-driven (MockBackend in 2.6 must satisfy them).

**Interfaces (Produces):**
```swift
func runContainer(_ config: RunConfiguration) async throws -> String
func buildImage(_ config: BuildConfiguration) -> AsyncThrowingStream<OutputLine, Error>
func copyToContainer(source: URL, containerID: String, containerPath: String) async throws
func copyFromContainer(containerID: String, containerPath: String, destination: URL) async throws
func fetchLogs(container id: String, tail: Int?, boot: Bool) async throws -> [OutputLine]
func listContainerDirectory(id: String, path: String) async throws -> [ContainerFileEntry]
```
- [ ] **Step 1:** Add the six methods to the protocol (under the Containers / Images sections). **Step 2:** `swift build` fails until adapters conform (expected — implemented next). **Step 3: Commit** with Task 2.6 (don't leave the tree uncompilable in its own commit; bundle 2.4+2.5+2.6).

### Task 2.5: `CLICommand` factories + `CLIContainerBackend` impls

**Files:**
- Modify: `Sources/CapsuleCLIBackend/CLICommand.swift`, `Sources/CapsuleCLIBackend/CLIContainerBackend.swift`
- Test: `Tests/CapsuleUnitTests/CLICommandTests.swift`, `Tests/CapsuleUnitTests/CLIContainerBackendTests.swift`

**Interfaces:**
- Consumes: `RunConfiguration.arguments`, `BuildConfiguration.arguments`, `runChecked`, `runner.run`, `runner.stream`, `runRaw`.

- [ ] **Step 1: Failing tests** (CLICommand + backend via `StubProcessRunner`):
```swift
// CLICommandTests
func testCopyToArgvUsesCopySubcommand() {
    XCTAssertEqual(CLICommand.copy(source: "/h/f.txt", destination: "c1:/app/f.txt"),
        ["copy", "/h/f.txt", "c1:/app/f.txt"])
}
func testFetchLogsArgvWithTail() {
    XCTAssertEqual(CLICommand.fetchLogs(container: "c1", tail: 100, boot: false),
        ["logs", "-n", "100", "c1"])
}
func testListDirectoryArgvUsesExecLs() {
    XCTAssertEqual(CLICommand.listDirectory(id: "c1", path: "/etc"),
        ["exec", "c1", "ls", "-la", "/etc"])
}
// CLIContainerBackendTests
func testRunContainerReturnsParsedID() async throws {
    let stub = StubProcessRunner()
    stub.result = CommandResult(exitCode: 0, stdout: "abc123def\n", stderr: "")
    let id = try await makeBackend(stub).runContainer(
        RunConfiguration(image: "nginx", name: nil, command: [], env: [], publishPorts: [],
            volumes: [], workdir: nil, user: nil, interactive: false, tty: false,
            detach: true, remove: false))
    XCTAssertEqual(id, "abc123def")
    XCTAssertEqual(stub.lastCall, ["run", "-d", "nginx"])
}
func testBuildImageStreamsAndBuildsArgv() async throws {
    let stub = StubProcessRunner()
    stub.streamLines = [OutputLine(source: .stdout, text: "Step 1/2")]
    var got: [String] = []
    for try await l in makeBackend(stub).buildImage(BuildConfiguration(
        contextDirectory: URL(fileURLWithPath: "/p"), tag: "t:1", dockerfile: nil,
        buildArgs: [], noCache: false, plainProgress: false)) { got.append(l.text) }
    XCTAssertEqual(got, ["Step 1/2"])
    XCTAssertEqual(stub.lastCall, ["build", "--tag", "t:1", "/p"])
}
func testListDirectoryParsesLsLeniently() async throws {
    let stub = StubProcessRunner()
    stub.result = CommandResult(exitCode: 0,
        stdout: "total 8\ndrwxr-xr-x 2 root root 4096 Jun 1 00:00 bin\n-rw-r--r-- 1 root root 220 Jun 1 00:00 .bashrc\n",
        stderr: "")
    let rows = try await makeBackend(stub).listContainerDirectory(id: "c1", path: "/")
    XCTAssertTrue(rows.contains { $0.name == "bin" && $0.isDirectory })
    XCTAssertTrue(rows.contains { $0.name == ".bashrc" && !$0.isDirectory })
}
```
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement**:
  - `CLICommand.run(_ c: RunConfiguration) -> [String] { c.arguments }`, `build(_:)` likewise; `copy(source:destination:)`→`["copy", source, destination]`; `fetchLogs(container:tail:boot:)`→`ArgumentBuilder("logs").option("--boot", enabled: boot).flag("-n", tail.map(String.init)).adding(id)`; `listDirectory(id:path:)`→`["exec", id, "ls", "-la", path]`.
  - `CLIContainerBackend.runContainer`: `let r = try await runChecked(CLICommand.run(config)); return r.stdout.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""`.
  - `buildImage`: `runner.stream(CLICommand.build(config), environment: [:])`.
  - `copyToContainer`: `_ = try await runChecked(CLICommand.copy(source: source.path, destination: "\(containerID):\(containerPath)"))`; `copyFromContainer` mirror (`"\(containerID):\(containerPath)"` source, `destination.path` dest).
  - `fetchLogs`: run `CLICommand.fetchLogs`, split stdout into `OutputLine(.stdout)` lines.
  - `listContainerDirectory`: `let out = try await runRaw(CLICommand.listDirectory(...))`; if `out.exitCode != 0` throw `BackendError.nonZeroExit`; parse each line: skip `total …`; split on whitespace; first char `d` ⇒ directory; size = field index 4 if numeric; name = the remainder after field 8 (join to preserve spaces). Lenient: ignore malformed lines.
- [ ] **Step 4: Run** both suites → PASS.
- [ ] **Step 5: Commit** `feat(backend): run/build/copy/fetchLogs/listDirectory CLI adapter + argv`.

### Task 2.6: `MockBackend` implementations

**Files:**
- Modify: `Sources/CapsuleBackend/MockBackend.swift`
- Test: `Tests/CapsuleUnitTests/MockBackendTests.swift`

- [ ] **Step 1: Failing tests** — assert each new method records its inputs / returns seeded data and honors `failure`:
```swift
func testMockRunContainerRecordsConfigAndReturnsID() async throws {
    let mock = MockBackend()
    let id = try await mock.runContainer(RunConfiguration(image: "nginx", name: "web",
        command: [], env: [], publishPorts: [], volumes: [], workdir: nil, user: nil,
        interactive: false, tty: false, detach: true, remove: false))
    XCTAssertEqual(mock.lastRunConfig?.image, "nginx")
    XCTAssertFalse(id.isEmpty)
}
func testMockCopyRecordsEndpoints() async throws { /* lastCopy == (.toContainer, url, "c1", "/app") */ }
func testMockListDirectoryReturnsSeeded() async throws { /* seeded entries */ }
func testMockBuildStreamsSeededLines() async throws { /* seededStream-style */ }
```
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — add stored `lastRunConfig`, `lastBuildConfig`, `lastCopy: (direction, URL, String, String)?`, `lastListedPath`, seeded `containerFiles: [ContainerFileEntry]`. `runContainer` records + returns a synthetic id (e.g. `"mock-\(config.image)"`), honoring `failure`. `buildImage` → seeded stream. `copy*` record. `fetchLogs` → seeded `logLines`. `listContainerDirectory` → seeded `containerFiles` (or throw `failure`).
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** `feat(backend): MockBackend run/build/copy/logs/listDirectory`.

---

## Phase 3 — Run (model + sheet + triage)

### Task 3.1: `RunDraft` + `RunModel.validatedConfiguration` + `commandPreview`

**Files:**
- Create: `Sources/CapsuleDomain/RunModel.swift`
- Test: `Tests/CapsuleUnitTests/RunModelTests.swift`

**Interfaces:**
- Produces: `struct RunDraft` (image, name, `portRows: [String]`, `envRows: [String]`, `volumeRows: [String]`, workdir, command string, interactive, tty, detach, remove); `RunModel.draft`; `func validatedConfiguration() -> Result<RunConfiguration, CapsuleError>`; `var commandPreview: String`.

- [ ] **Step 1: Failing tests**:
```swift
func testValidationRejectsEmptyImage() {
    let m = RunModel(backend: MockBackend(), taskCenter: TaskCenter())
    m.draft.image = "  "
    if case .failure(let e) = m.validatedConfiguration(),
       case .invalidInput(let field, _) = e { XCTAssertEqual(field, "image") }
    else { XCTFail() }
}
func testCommandPreviewReflectsToggles() {
    let m = RunModel(backend: MockBackend(), taskCenter: TaskCenter())
    m.draft.image = "alpine"; m.draft.interactive = true; m.draft.tty = true
    XCTAssertEqual(m.commandPreview, "container run -i -t alpine")
}
func testCommandSplittingHandlesQuotedArgs() {
    let m = RunModel(backend: MockBackend(), taskCenter: TaskCenter())
    m.draft.image = "alpine"; m.draft.command = "sh -c \"echo hi\""
    if case .success(let c) = m.validatedConfiguration() {
        XCTAssertEqual(c.command, ["sh", "-c", "echo hi"])
    } else { XCTFail() }
}
```
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — `validatedConfiguration` trims image (empty ⇒ `.invalidInput(field:"image")`), drops blank rows, splits `command` with a small shell-like tokenizer (respect double quotes), builds the `RunConfiguration`. `commandPreview` = `"container " + (try? config).arguments.joined(" ")` or `"container run"` while image is empty.
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** `feat(run): RunModel draft validation + command preview`.

### Task 3.2: `RunModel.runDetached` / `runInTerminal` + triage state

**Files:**
- Modify: `Sources/CapsuleDomain/RunModel.swift`
- Test: `Tests/CapsuleUnitTests/RunModelTests.swift`

**Interfaces:**
- Consumes: `taskCenter`, `launchOrCopy` (injected `terminalAvailable`/`launchTerminal`/`copyCommand` like `ContainerLifecycleModel`), `reloadList`.
- Produces: `runDetached()` (registers `.run` task, onSuccess reload), `runInTerminal()` (emits `TerminalRequest(kind:.runInteractive)`), `lastFailedConfig`, triage helpers `resolveImageReference`, `retryInTerminal()`.

- [ ] **Step 1: Failing tests**:
```swift
func testRunDetachedRegistersTask() async {
    let center = TaskCenter()
    let m = RunModel(backend: MockBackend(), taskCenter: center)
    m.draft.image = "nginx"; m.draft.detach = true
    m.runDetached(); await center.tasks.first?.wait()
    XCTAssertEqual(center.tasks.first?.kind, .run)
}
func testRunInTerminalEmitsInteractiveRequest() {
    var launched: TerminalRequest?
    let m = RunModel(backend: MockBackend(), taskCenter: TaskCenter(),
        terminalAvailable: { true }, launchTerminal: { launched = $0 })
    m.draft.image = "alpine"
    m.runInTerminal()
    XCTAssertEqual(launched?.argv, ["container", "run", "-i", "-t", "alpine"])
    XCTAssertEqual(launched?.kind, .runInteractive)
}
```
- [ ] **Step 2: Run** → FAIL (also add `.runInteractive` to `TerminalRequest.Kind`).
- [ ] **Step 3: Implement** — add `.runInteractive` case to `TerminalRequest.Kind`; `runInTerminal` forces `interactive=true,tty=true,detach=false`, builds config, `launchOrCopy(TerminalRequest(containerID:nil, title:"Run · \(image)", argv:["container"]+config.arguments, kind:.runInteractive))`. `runDetached` forces `detach=true`, `taskCenter.runAsync(kind:.run, title:"Run \(image)", onSuccess: reloadList) { _ = try await backend.runContainer(config) }`, and on failure stores `lastFailedConfig` for triage.
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** `feat(run): detached-run task + interactive terminal launch + triage state`.

### Task 3.3: `QuickRunSheet` + Run-Image context + triage view (UI)

**Files:**
- Create: `Sources/CapsuleUI/QuickRunSheet.swift`, `Sources/CapsuleUI/RunFailureTriageView.swift`
- Modify: `Sources/CapsuleUI/ImageListView.swift` (Run Image… toolbar/context, `ImageSheet.run(image:)` case)

- [ ] **Step 1:** `QuickRunSheet` — bound to `RunModel.draft`: image field, name, dynamic +/- rows for ports/env/volumes (each a `TextField` list with add/remove), workdir, command, toggles (Interactive (i+t) / Detach / Remove), a monospaced **Command preview** line (`model.commandPreview`), inline validation error, and a Run button → `runInTerminal()` when interactive else `runDetached()` then dismiss. Detach + interactive are mutually exclusive (interactive disables detach).
- [ ] **Step 2:** `ImageListView` — add `.run(image:)` to `ImageSheet`, a **Run Image…** context item + toolbar button passing the row's reference; present `QuickRunSheet` with the image prefilled.
- [ ] **Step 3:** `RunFailureTriageView` — given a failed `.run` task + the `RunModel`, show three buttons: **Resolve Image** (opens Pull sheet for `lastFailedConfig.image`), **Inspect Logs** (reveals the task transcript / logs), **Retry in Terminal** (`model.retryInTerminal()`), plus the raw transcript.
- [ ] **Step 4:** `swift build` + `make format`/`lint` clean. **Step 5: Commit** `feat(run): Quick Run sheet, Run Image action, failure triage panel`.

---

## Phase 4 — Build (model + sheet)

### Task 4.1: `BuildDraft` + `BuildModel` (presets, build, retryPlain, validation)

**Files:**
- Create: `Sources/CapsuleDomain/BuildModel.swift`
- Test: `Tests/CapsuleUnitTests/BuildModelTests.swift`

**Interfaces:**
- Produces: `struct BuildDraft` (contextDirectory: URL?, tag, dockerfile, `buildArgRows: [String]`, noCache, preset: `BuildPreset`); `enum BuildPreset { case standard, noCache, plainProgress }`; `validatedConfiguration() -> Result<BuildConfiguration, CapsuleError>`; `build()` (streaming `.build` task, onSuccess reload images); `retryPlain(_ task:)`.

- [ ] **Step 1: Failing tests**:
```swift
func testValidationRequiresContextAndTag() {
    let m = BuildModel(backend: MockBackend(), taskCenter: TaskCenter())
    if case .failure(let e) = m.validatedConfiguration(),
       case .invalidInput(let field, _) = e { XCTAssertEqual(field, "context") } else { XCTFail() }
}
func testPresetMapsToConfig() {
    let m = BuildModel(backend: MockBackend(), taskCenter: TaskCenter())
    m.draft.contextDirectory = URL(fileURLWithPath: "/p"); m.draft.tag = "t:1"
    m.draft.preset = .plainProgress
    if case .success(let c) = m.validatedConfiguration() { XCTAssertTrue(c.plainProgress) } else { XCTFail() }
}
func testBuildRegistersStreamingTask() async {
    let center = TaskCenter()
    let m = BuildModel(backend: MockBackend(), taskCenter: center)
    m.draft.contextDirectory = URL(fileURLWithPath: "/p"); m.draft.tag = "t:1"
    m.build(); await center.tasks.first?.wait()
    XCTAssertEqual(center.tasks.first?.kind, .build)
}
```
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — validation: nil context ⇒ `.invalidInput(field:"context")`; empty tag ⇒ `.invalidInput(field:"tag")`. Preset sets `noCache`/`plainProgress` (noCache preset ⇒ noCache true; plainProgress ⇒ plainProgress true; explicit toggles OR with preset). `build()` → `taskCenter.runStreaming(kind:.build, title:"Build \(tag)", onSuccess: reloadList) { backend.buildImage(config) }`, storing the task. `retryPlain(task)` rebuilds config with `plainProgress=true` and re-runs (new task or reuse).
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** `feat(build): BuildModel with presets, streaming build, plain-progress retry`.

### Task 4.2: `BuildSheet` (folder drop, presets, live pane, export, plain retry)

**Files:**
- Create: `Sources/CapsuleUI/BuildSheet.swift`
- Modify: `Sources/CapsuleUI/ImageListView.swift` (Build… toolbar + `ImageSheet.build`)

- [ ] **Step 1:** `BuildSheet` — a **drop zone** (`.onDrop(of: [.fileURL])` resolving a folder URL into `draft.contextDirectory`, plus a **Choose…** `NSOpenPanel` with `canChooseDirectories`), the chosen path shown; tag field (required marker); Dockerfile field; +/- build-arg rows; preset `Picker`; no-cache toggle; a **Build** button → `model.build()`. While the build task runs/finishes, embed `TaskTranscriptView(task:)` (full streaming output, never hidden). Footer: **Export Transcript…** (`NSSavePanel` writing `task.transcriptText`) and, on failure, **Retry with plain progress** (`model.retryPlain(task)`).
- [ ] **Step 2:** `ImageListView` — `Build…` toolbar button → `activeSheet = .build`.
- [ ] **Step 3:** `swift build` + format/lint clean. **Step 4: Commit** `feat(build): Build sheet with folder drop, live transcript, export + plain retry`.

---

## Phase 5 — Exec / interactive + Open-in-Terminal fallback

### Task 5.1: Exec + machine-shell entry points on `ContainerLifecycleModel`

**Files:**
- Modify: `Sources/CapsuleDomain/ContainerLifecycleModel.swift`
- Test: `Tests/CapsuleUnitTests/ContainerLifecycleModelTests.swift` (+ `TerminalRequestTests.swift`)

**Interfaces:**
- Produces: `execShell(id:command:)` (custom command, default `["sh"]`) and `openMachineShell(name:)`.

- [ ] **Step 1: Failing tests**:
```swift
func testExecShellWithCustomCommand() {
    var req: TerminalRequest?
    let m = ContainerLifecycleModel(backend: MockBackend(),
        terminalAvailable: { true }, launchTerminal: { req = $0 })
    m.execShell(id: "c1", command: ["bash", "-l"])
    XCTAssertEqual(req?.argv, ["container", "exec", "-it", "c1", "bash", "-l"])
}
func testMachineShellArgv() {
    var req: TerminalRequest?
    let m = ContainerLifecycleModel(backend: MockBackend(),
        terminalAvailable: { true }, launchTerminal: { req = $0 })
    m.openMachineShell(name: "default")
    XCTAssertEqual(req?.argv, ["container", "machine", "run", "-it", "-n", "default"])
}
```
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — `execShell(id:command:)` builds `["container","exec","-it",id] + command` via `launchOrCopy` (kind `.execShell`); keep existing `openShell` as `execShell(id:command:["sh"])`. `openMachineShell(name:)` → `["container","machine","run","-it","-n",name]` (kind `.execShell`).
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** `feat(exec): custom exec command + machine shell terminal entry points`.

### Task 5.2: `ExecSheet` + Open-in-Terminal.app fallback

**Files:**
- Create: `Sources/CapsuleUI/ExecSheet.swift`
- Modify: `Sources/CapsuleUI/ContainerListView.swift` (Exec… context/toolbar, `ContainerSheet.exec(id:)`), `Sources/CapsuleApp/AppEnvironment.swift` (inject an `openInTerminalApp` closure into the copy fallback path)

**Interfaces:**
- Consumes: `lifecycle.execShell(id:command:)`.

- [ ] **Step 1:** `ExecSheet` — container id (read-only), command field (default `sh`), interactive+tty toggle (on by default), a command preview, Run → `lifecycle.execShell(id:command: tokenized)` then dismiss.
- [ ] **Step 2:** `ContainerListView` — Exec… context item + `ContainerSheet.exec(id:)`.
- [ ] **Step 3:** In `AppEnvironment.live()`, extend the terminal fallback: keep clipboard copy, and add an **Open in Terminal.app** path — write argv to a temp `.command` script (chmod +x) and `NSWorkspace.shared.open` it (or `open -a Terminal`). Expose this as a `ShellActions`/lifecycle seam so the AttachConsole/StartAttach "terminal unavailable" affordance and the exec sheet can offer it. (Only `CapsuleApp` touches `NSWorkspace`.)
- [ ] **Step 4:** `swift build` + format/lint. **Step 5: Commit** `feat(exec): Exec sheet + Open-in-Terminal.app detach fallback`.

---

## Phase 6 — Logs (model + pane + detachable window)

### Task 6.1: `LogsModel`

**Files:**
- Create: `Sources/CapsuleDomain/LogsModel.swift`
- Test: `Tests/CapsuleUnitTests/LogsModelTests.swift`

**Interfaces:**
- Produces: `LogsModel` with `lines: [LogLine]`, `follow`, `tail: Int?`, `boot`, `searchText`, `filteredLines`, `start(id:)`, `stop()`, `transcriptText`, `containerID: String?`.

- [ ] **Step 1: Failing tests**:
```swift
func testSnapshotPopulatesLines() async {
    let mock = MockBackend(); mock.logLines = [OutputLine(source: .stdout, text: "hello")]
    let m = LogsModel(backend: mock); m.follow = false
    await m.startAndWait(id: "c1")     // test helper that awaits the load task
    XCTAssertTrue(m.lines.contains { $0.text == "hello" })
}
func testSearchFilters() {
    let m = LogsModel(backend: MockBackend())
    m.appendForTest(["alpha", "beta", "alpha-2"]); m.searchText = "alpha"
    XCTAssertEqual(m.filteredLines.map(\.text), ["alpha", "alpha-2"])
}
func testStopCancelsFollow() async { /* neverEndingLogStream → start(follow) → stop() ends */ }
```
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — `start(id:)`: cancel prior task; if `follow` use `backend.followLogs` else `backend.fetchLogs(container:id, tail:tail, boot:boot)`; append `LogLine`s. `filteredLines` = case-insensitive contains on `searchText` (empty ⇒ all). `stop()` cancels. `transcriptText` joins lines. Provide test helpers `startAndWait`/`appendForTest`.
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** `feat(logs): LogsModel with follow/snapshot/tail/boot/search/transcript`.

### Task 6.2: `LogsPaneView` + detachable `LogWindow` scene + menu

**Files:**
- Create: `Sources/CapsuleUI/LogsPaneView.swift`, `Sources/CapsuleUI/LogWindow.swift`
- Modify: `Sources/CapsuleApp/CapsuleScene.swift` (add `Window`), `Sources/CapsuleApp/CapsuleCommands.swift` (View ▸ Open Log Window), `Sources/CapsuleApp/AppEnvironment.swift` (add `logsModel`)

- [ ] **Step 1:** `LogsPaneView(model:)` — toolbar row: Follow toggle, Tail field (number), Boot toggle, `.searchable`/search field, **Save…** (`NSSavePanel` `.log`/`.txt` writing `transcriptText`), and an **Open in Window** button; a monospaced auto-scrolling scrollback of `filteredLines`. Reused by both the pane and the window.
- [ ] **Step 2:** `LogWindow` + `Window("Logs", id: LogWindow.id) { LogsPaneView(model: logsModel) }` in `CapsuleScene`; a `View ▸ Open Log Window` command that opens it (`@Environment(\.openWindow)`), and a per-container **Logs** action that sets `logsModel.start(id:)` then opens the window.
- [ ] **Step 3:** `swift build` + format/lint. **Step 4: Commit** `feat(logs): logs pane + detachable log window with follow/search/save`.

---

## Phase 7 — Copy (model + sheet + file browser)

### Task 7.1: `CopyModel` (direction, validation, copy task, browse)

**Files:**
- Create: `Sources/CapsuleDomain/CopyModel.swift`
- Test: `Tests/CapsuleUnitTests/CopyModelTests.swift`

**Interfaces:**
- Produces: `enum CopyDirection { case toContainer, fromContainer }`; `CopyModel` with `direction`, `hostURL: URL?`, `containerID`, `containerPath`, `validationMessage: String?`, `canCopy: Bool`, `copy()` (registers `.copy` task), `browse(path:) async -> [ContainerFileEntry]`.

- [ ] **Step 1: Failing tests**:
```swift
func testValidationRequiresAbsoluteContainerPathAndEndpoints() {
    let m = CopyModel(backend: MockBackend(), taskCenter: TaskCenter())
    m.containerID = "c1"; m.containerPath = "relative"; m.hostURL = URL(fileURLWithPath: "/h")
    XCTAssertFalse(m.canCopy)
    XCTAssertNotNil(m.validationMessage)        // explains id:/abs/path requirement
    m.containerPath = "/app"
    XCTAssertTrue(m.canCopy)
}
func testCopyToContainerRegistersTaskAndCallsBackend() async {
    let mock = MockBackend(); let center = TaskCenter()
    let m = CopyModel(backend: mock, taskCenter: center)
    m.direction = .toContainer; m.hostURL = URL(fileURLWithPath: "/h/f"); m.containerID = "c1"; m.containerPath = "/app/f"
    m.copy(); await center.tasks.first?.wait()
    XCTAssertEqual(center.tasks.first?.kind, .copy)
    XCTAssertEqual(mock.lastCopy?.containerID, "c1")
}
```
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — `canCopy`/`validationMessage`: require `hostURL != nil`, non-empty `containerID`, and `containerPath` starting with `/` (else message `Container path must be absolute, e.g. c1:/app/file`). `copy()` → `taskCenter.runAsync(kind:.copy, title:"Copy")` calling `copyToContainer`/`copyFromContainer` by direction. `browse(path:)` → `try? await backend.listContainerDirectory(id:containerID, path:path) ?? []`.
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** `feat(copy): CopyModel with path validation, copy task, container browse`.

### Task 7.2: `CopySheet` + host/container panels + drag/drop

**Files:**
- Create: `Sources/CapsuleUI/CopySheet.swift`
- Modify: `Sources/CapsuleUI/ContainerListView.swift` (Copy Files… context/toolbar, `ContainerSheet.copy(id:)`)

- [ ] **Step 1:** `CopySheet` — a direction segmented control; a **host panel** (drop target + Choose… via `NSOpenPanel`, showing the chosen path) and a **container panel** (id field prefilled, path field with inline example text `c1:/app/file`, and a **Browse** disclosure listing `ContainerFileEntry` rows from `model.browse(path:)` — tapping a row sets `containerPath`); drag a host file onto the container panel sets `hostURL`. A validation line (`model.validationMessage`) and a **Copy** button gated on `model.canCopy`.
- [ ] **Step 2:** `ContainerListView` — Copy Files… context item + `ContainerSheet.copy(id:)`.
- [ ] **Step 3:** `swift build` + format/lint. **Step 4: Commit** `feat(copy): copy sheet with host/container panels, drag-drop, path examples`.

---

## Phase 8 — Composition, arch-guard, full verification

### Task 8.1: Wire new models into the composition root

**Files:**
- Modify: `Sources/CapsuleApp/AppEnvironment.swift`, `Sources/CapsuleApp/CapsuleScene.swift`, `Sources/CapsuleUI/AppShellView.swift`, `Sources/CapsuleUI/RootView.swift`, `Sources/CapsuleUI/ContentColumnView.swift`
- Test: `Tests/CapsuleUnitTests/CompositionTests.swift`, `Tests/CapsuleUnitTests/AppEnvironmentActionsTests.swift`

**Interfaces:**
- Produces: `AppEnvironment.runModel/buildModel/logsModel/copyModel`; threaded through `CapsuleScene` → `RootView` → `AppShellView`.

- [ ] **Step 1: Failing test** (composition exposes models + export now registers a task):
```swift
func testEnvironmentExposesM7Models() {
    let env = AppEnvironment.live()
    XCTAssertNotNil(env.runModel); XCTAssertNotNil(env.buildModel)
    XCTAssertNotNil(env.logsModel); XCTAssertNotNil(env.copyModel)
}
```
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — construct the four models in `live()` sharing `taskCenter`, normalize, `shell.appendActivity`, reloads, and the terminal seams (reuse the lifecycle model's `terminalAvailable`/`launchTerminal`/`copyCommand`); inject `taskCenter` into `ContainerLifecycleModel` (export) and `SystemStatusModel` (start). Thread the models through `CapsuleScene`/`RootView`/`AppShellView`; surface the sheets from `ContainerListView`/`ImageListView` and the logs window from `CapsuleScene`.
- [ ] **Step 4: Run** the suite → PASS.
- [ ] **Step 5: Commit** `feat(app): wire Run/Build/Logs/Copy models + log window into composition`.

### Task 8.2: Arch-guard, format, full suite

- [ ] **Step 1:** `make arch` (or `swift test --filter ArchitectureGuardTests`) → PASS (no UI→Backend, no Domain→Process; confirm the new files respect it — e.g. `AppEnvironment` is the only `NSWorkspace` site).
- [ ] **Step 2:** `make format` then `make lint` → clean.
- [ ] **Step 3:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` → all green (integration tests may skip).
- [ ] **Step 4:** `make app` builds the bundle.
- [ ] **Step 5: Commit** any formatting `chore: swift-format` if needed.

### Task 8.3: Live GUI smoke + adversarial review

- [ ] **Step 1:** Launch the app (`make run` or open the built bundle). With the container service running, smoke each surface: a **detached run** of `alpine echo hi` (task appears, succeeds, list reloads); an **interactive run** of `alpine sh` (terminal tab); a **build** of a tiny context (live transcript, export, plain-progress retry on a forced failure); **exec -it** into a running container; **logs** follow + search + save + detach window; **copy** a host file into a container with path validation + browse; **cancel** a long task; verify export + system-start now show as tasks.
- [ ] **Step 2:** Dispatch an adversarial subagent code review (as M6 did) over the diff; fix any Critical/High findings (e.g. argv edge cases, cancel races, drag/drop URL resolution, terminal teardown).
- [ ] **Step 3:** Update the milestone memory; push the branch; prepare the PR body (gh may be unavailable → save body to scratch + provide the compare URL).

## Self-Review (plan vs spec)

- **Activity model** (cancel/progress/transcript/retry/queue, export+system-start tasks): Tasks 1.1–1.6 ✓.
- **Run** (quick sheet, inspector=preview, Run Image…, terminal attach, triage): Tasks 3.1–3.3 ✓.
- **Build** (folder drop, presets, live stream, export, plain retry): Tasks 2.2, 4.1–4.2 ✓.
- **Exec/interactive** (terminal, custom command, machine shell, Open-in-Terminal fallback, rerun): Tasks 5.1–5.2 (rerun via existing Restart banner) ✓.
- **Logs** (follow/search/save, detach window): Tasks 6.1–6.2 ✓.
- **Copy** (path validation, drag/drop, container browser, examples): Tasks 2.3/2.5, 7.1–7.2 ✓.
- **Backend** additions + Mock + argv tests: Tasks 2.1–2.6 ✓.
- **Composition + arch + verify**: Tasks 8.1–8.3 ✓.
- Type consistency: `RunConfiguration.arguments`, `BuildConfiguration.arguments`, `OperationKind.{build,run,export,systemStart,copy}`, `TaskState.cancelled`, `TerminalRequest.Kind.runInteractive`, `ContainerFileEntry`, model names (`RunModel/BuildModel/LogsModel/CopyModel`) used consistently across tasks. No placeholder steps.
</content>
