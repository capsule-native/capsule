# Milestone 5A · Containers Browser + Inspector — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the live containers browser (list, search, state filter, persisted saved scopes, multi-select, keyboard-navigable rows) and a trailing inspector with a friendly Summary tab and a Raw JSON tab, all backed by the existing `ContainerBackend` port and tested against `MockBackend`.

**Architecture:** Ports & Adapters, strictly layered (UI → Domain → Backend port). A new domain `@Observable @MainActor ContainerBrowserModel` owns list + query (search / state filter / selection) + saved scopes (persisted via an injected `ScopeStore`). The UI is a thin `Table`-based view plus a `TabView` inspector that bind only to the domain model. No new mutating port methods — lifecycle actions are Milestone 5B.

**Tech Stack:** Swift 6, SwiftUI (macOS 26+), `Observation`, XCTest. Build/test via the `Makefile` (`make build` / `make test` / `make ci`).

## Global Constraints

- Apple silicon only, macOS 26+; Swift 6 language mode.
- **Architecture guard (enforced by `Tests/CapsuleUnitTests/ArchitectureGuardTests` + `Scripts/check-architecture.sh`):** `CapsuleUI` imports **no** Backend module; `CapsuleDomain` imports **no** UI and **no** `Foundation.Process`. Therefore no `CapsuleBackend` type (e.g. `Parsed`, `ContainerSummary`) may appear in a `CapsuleUI` signature — the domain maps them first.
- Every source file begins with the standard license header (pre-commit hook `license headers` enforces it). Copy the header from any existing file in the same module.
- Tests run under Xcode's toolchain: prefix `swift test` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the `Makefile` already exports this for `make test`). Filter a single suite with `swift test --filter <SuiteName>`.
- `make ci` must stay green: zero-warning build, `swift-format --strict`, arch guard, license headers, unit + integration tests.
- TDD: write the failing test first, watch it fail, implement minimally, watch it pass, commit. Small, frequent commits. End commit messages with the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.

---

### Task 1: Backend — `ContainerSummary.createdAt` + richer mock data

**Files:**
- Modify: `Sources/CapsuleBackend/BackendValueTypes.swift` (the `ContainerSummary` struct)
- Modify: `Sources/CapsuleBackend/MockBackend.swift` (`sampleContainers`)
- Test: `Tests/CapsuleUnitTests/MockBackendTests.swift`

**Interfaces:**
- Produces: `ContainerSummary.createdAt: String?` (raw ISO-8601 from the wire, `nil` when absent); `MockBackend.sampleContainers` now has 3 rows with `createdAt` set and a mix of `running`/`stopped`.

- [ ] **Step 1: Write the failing test** — add to `MockBackendTests`:

```swift
func testSampleContainersAreRicherForBrowser() async throws {
    let all = try await MockBackend().listContainers(all: true)
    XCTAssertGreaterThanOrEqual(all.count, 3)
    XCTAssertTrue(all.contains { $0.state == "running" })
    XCTAssertTrue(all.contains { $0.state == "stopped" })
    XCTAssertTrue(all.allSatisfy { $0.createdAt != nil })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter MockBackendTests`
Expected: FAIL — `createdAt` is not a member of `ContainerSummary` (compile error), or count < 3.

- [ ] **Step 3: Add the field.** In `BackendValueTypes.swift`, add to `ContainerSummary` (after `ip`):

```swift
    /// The container's creation timestamp as the raw ISO-8601 string the CLI emits.
    public var createdAt: String?
```

Update the initializer signature and body:

```swift
    public init(
        id: String, name: String, image: String, state: String,
        ip: String? = nil, createdAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.ip = ip
        self.createdAt = createdAt
    }
```

- [ ] **Step 4: Enrich the mock.** Replace `MockBackend.sampleContainers` with:

```swift
    public static let sampleContainers: [ContainerSummary] = [
        ContainerSummary(
            id: "a1b2c3d4",
            name: "web",
            image: "docker.io/library/alpine:latest",
            state: "running",
            ip: "192.168.64.3",
            createdAt: "2026-06-20T09:15:00Z"
        ),
        ContainerSummary(
            id: "e5f6a7b8",
            name: "db",
            image: "docker.io/library/postgres:16",
            state: "stopped",
            createdAt: "2026-06-18T14:02:30Z"
        ),
        ContainerSummary(
            id: "0c1d2e3f",
            name: "cache",
            image: "docker.io/library/redis:7",
            state: "running",
            ip: "192.168.64.4",
            createdAt: "2026-06-21T11:47:10Z"
        ),
    ]
```

- [ ] **Step 5: Run test to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter MockBackendTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/CapsuleBackend Tests/CapsuleUnitTests/MockBackendTests.swift
git commit -m "feat(backend): add createdAt to ContainerSummary + richer mock data

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: CLI — parse `createdAt` from the real list JSON

**Files:**
- Modify: `Sources/CapsuleCLIBackend/OutputParser.swift` (`parseContainers`)
- Test: `Tests/CapsuleUnitTests/OutputParserTests.swift`

**Interfaces:**
- Consumes: `CLIContainerRecord.Configuration.creationDate` (already declared in `WireModels.swift` as `String?`).
- Produces: `OutputParser.parseContainers` now populates `ContainerSummary.createdAt` from `configuration.creationDate`.

- [ ] **Step 1: Write the failing test** — add to `OutputParserTests`:

```swift
func testParseContainersExtractsCreationDate() throws {
    let json = """
    [{"id":"abc","configuration":{"id":"web",\
    "image":{"reference":"docker.io/library/alpine:latest"},\
    "creationDate":"2026-06-20T09:15:00Z"},\
    "status":{"state":"running","networks":[]}}]
    """
    let rows = try OutputParser.parseContainers(Data(json.utf8))
    XCTAssertEqual(rows.first?.createdAt, "2026-06-20T09:15:00Z")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OutputParserTests`
Expected: FAIL — `createdAt` is `nil` (not yet mapped).

- [ ] **Step 3: Map the field.** In `parseContainers`, add `createdAt` to the `ContainerSummary(...)` construction:

```swift
            ContainerSummary(
                id: record.id,
                name: record.configuration.id,
                image: record.configuration.image.reference,
                state: record.status.state,
                ip: record.status.networks.lazy.compactMap(\.ipAddress).first,
                createdAt: record.configuration.creationDate
            )
```

- [ ] **Step 4: Run test to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OutputParserTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CapsuleCLIBackend/OutputParser.swift Tests/CapsuleUnitTests/OutputParserTests.swift
git commit -m "feat(cli): map creationDate into ContainerSummary.createdAt

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Domain — `Container` gains `ip`, `createdAt`, `shortID`

**Files:**
- Modify: `Sources/CapsuleDomain/Resource.swift` (the `Container` struct + `init(summary:)`)
- Test: `Tests/CapsuleUnitTests/DomainModelTests.swift`

**Interfaces:**
- Consumes: `ContainerSummary.ip`, `ContainerSummary.createdAt` (Tasks 1–2).
- Produces: `Container.ip: String?`, `Container.createdAt: Date?`, `Container.shortID: String`. Mapping parses ISO-8601 leniently (unparseable → `nil`).

- [ ] **Step 1: Write the failing test** — add to `DomainModelTests`:

```swift
func testContainerMapsIPAndCreationDate() {
    let summary = ContainerSummary(
        id: "abcdef0123456789", name: "web", image: "nginx", state: "running",
        ip: "10.0.0.2", createdAt: "2026-06-20T09:15:00Z")
    let container = Container(summary: summary)
    XCTAssertEqual(container.ip, "10.0.0.2")
    XCTAssertNotNil(container.createdAt)
    XCTAssertEqual(container.shortID, "abcdef012345")
}

func testContainerCreationDateInvalidStringBecomesNil() {
    let summary = ContainerSummary(
        id: "id", name: "n", image: "i", state: "running", createdAt: "not-a-date")
    XCTAssertNil(Container(summary: summary).createdAt)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DomainModelTests`
Expected: FAIL — `ip` / `createdAt` / `shortID` are not members of `Container`.

- [ ] **Step 3: Extend `Container`.** In `Resource.swift`, replace the `Container` struct and its mapping extension:

```swift
public struct Container: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var image: String
    public var state: ContainerState
    public var ip: String?
    public var createdAt: Date?

    public init(
        id: String, name: String, image: String, state: ContainerState,
        ip: String? = nil, createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.ip = ip
        self.createdAt = createdAt
    }

    /// The leading 12 characters of the id, for compact display.
    public var shortID: String { String(id.prefix(12)) }
}

extension Container {
    /// Maps a backend summary into the domain model, parsing the ISO-8601 creation date.
    public init(summary: ContainerSummary) {
        self.init(
            id: summary.id,
            name: summary.name,
            image: summary.image,
            state: ContainerState(backendState: summary.state),
            ip: summary.ip,
            createdAt: summary.createdAt.flatMap(Container.parseDate)
        )
    }

    /// Parses an ISO-8601 timestamp, tolerating the presence or absence of fractional
    /// seconds, and returning `nil` for anything unrecognizable.
    static func parseDate(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DomainModelTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CapsuleDomain/Resource.swift Tests/CapsuleUnitTests/DomainModelTests.swift
git commit -m "feat(domain): enrich Container with ip, createdAt, shortID

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Domain — `ContainerStateFilter` + `ContainerScope`

**Files:**
- Create: `Sources/CapsuleDomain/ContainerScope.swift`
- Test: `Tests/CapsuleUnitTests/ContainerScopeTests.swift`

**Interfaces:**
- Consumes: `Container`, `ContainerState` (Task 3).
- Produces:
  - `enum ContainerStateFilter: String, Sendable, Codable, CaseIterable, Identifiable { case all, running, stopped, created }` with `title: String` and `func matches(_ state: ContainerState) -> Bool`.
  - `struct ContainerScope: Sendable, Codable, Equatable, Identifiable { var id, name: String; var stateFilter: ContainerStateFilter; var searchTerm: String }` with `static let all/running/stopped` and `static let builtIns: [ContainerScope]`.

- [ ] **Step 1: Write the failing test** — create `ContainerScopeTests.swift`:

```swift
//
//  ContainerScopeTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class ContainerScopeTests: XCTestCase {
    func testStateFilterMatching() {
        XCTAssertTrue(ContainerStateFilter.all.matches(.stopped))
        XCTAssertTrue(ContainerStateFilter.running.matches(.running))
        XCTAssertFalse(ContainerStateFilter.running.matches(.stopped))
        XCTAssertTrue(ContainerStateFilter.stopped.matches(.stopped))
        XCTAssertTrue(ContainerStateFilter.created.matches(.created))
    }

    func testBuiltInScopesAreAllRunningStopped() {
        XCTAssertEqual(
            ContainerScope.builtIns.map(\.stateFilter), [.all, .running, .stopped])
        XCTAssertEqual(ContainerScope.all.name, "All")
    }

    func testScopeRoundTripsThroughCodable() throws {
        let scope = ContainerScope(
            id: "x", name: "My View", stateFilter: .running, searchTerm: "web")
        let data = try JSONEncoder().encode([scope])
        let decoded = try JSONDecoder().decode([ContainerScope].self, from: data)
        XCTAssertEqual(decoded, [scope])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ContainerScopeTests`
Expected: FAIL — types not defined (compile error).

- [ ] **Step 3: Implement.** Create `Sources/CapsuleDomain/ContainerScope.swift`:

```swift
//
//  ContainerScope.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`.

import Foundation

/// A coarse filter over a container's lifecycle state.
public enum ContainerStateFilter: String, Sendable, Codable, CaseIterable, Identifiable {
    case all
    case running
    case stopped
    case created

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All"
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .created: return "Created"
        }
    }

    /// Whether a container's state passes this filter.
    public func matches(_ state: ContainerState) -> Bool {
        switch self {
        case .all: return true
        case .running: return state == .running
        case .stopped: return state == .stopped
        case .created: return state == .created
        }
    }
}

/// A named, saveable view over the container list: a state filter plus a captured search
/// term. Built-in scopes are constants; user scopes are saved copies persisted via a
/// ``ScopeStore``.
public struct ContainerScope: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var stateFilter: ContainerStateFilter
    public var searchTerm: String

    public init(id: String, name: String, stateFilter: ContainerStateFilter, searchTerm: String) {
        self.id = id
        self.name = name
        self.stateFilter = stateFilter
        self.searchTerm = searchTerm
    }

    public static let all = ContainerScope(
        id: "builtin.all", name: "All", stateFilter: .all, searchTerm: "")
    public static let running = ContainerScope(
        id: "builtin.running", name: "Running", stateFilter: .running, searchTerm: "")
    public static let stopped = ContainerScope(
        id: "builtin.stopped", name: "Stopped", stateFilter: .stopped, searchTerm: "")

    /// The scopes always offered, in display order.
    public static let builtIns: [ContainerScope] = [.all, .running, .stopped]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ContainerScopeTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CapsuleDomain/ContainerScope.swift Tests/CapsuleUnitTests/ContainerScopeTests.swift
git commit -m "feat(domain): ContainerStateFilter + ContainerScope value types

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Domain — `ScopeStore` protocol + `InMemoryScopeStore`

**Files:**
- Create: `Sources/CapsuleDomain/ScopeStore.swift`
- Test: `Tests/CapsuleUnitTests/ScopeStoreTests.swift`

**Interfaces:**
- Consumes: `ContainerScope` (Task 4).
- Produces:
  - `protocol ScopeStore: Sendable { func load() -> [ContainerScope]; func save(_ scopes: [ContainerScope]) }`.
  - `final class InMemoryScopeStore: ScopeStore` (thread-safe, reference semantics) usable as the model's default and as a test double.

- [ ] **Step 1: Write the failing test** — create `ScopeStoreTests.swift`:

```swift
//
//  ScopeStoreTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class ScopeStoreTests: XCTestCase {
    func testInMemoryStoreRoundTrips() {
        let store = InMemoryScopeStore()
        XCTAssertTrue(store.load().isEmpty)
        let scopes = [
            ContainerScope(id: "1", name: "A", stateFilter: .running, searchTerm: "x")
        ]
        store.save(scopes)
        XCTAssertEqual(store.load(), scopes)
    }

    func testInMemoryStoreSeedsInitialScopes() {
        let seed = [ContainerScope(id: "1", name: "A", stateFilter: .all, searchTerm: "")]
        XCTAssertEqual(InMemoryScopeStore(scopes: seed).load(), seed)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ScopeStoreTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Implement.** Create `Sources/CapsuleDomain/ScopeStore.swift`:

```swift
//
//  ScopeStore.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Concrete
//  persistence (UserDefaults) lives in the composition root so the domain owns no
//  storage-key knowledge; this file defines only the seam and an in-memory double.

import Foundation

/// Persists the user's saved container scopes. Injected into ``ContainerBrowserModel`` so
/// the domain stays free of any concrete persistence and remains unit-testable.
public protocol ScopeStore: Sendable {
    func load() -> [ContainerScope]
    func save(_ scopes: [ContainerScope])
}

/// A thread-safe, in-memory ``ScopeStore`` — the model's default (ephemeral) and the
/// test double.
public final class InMemoryScopeStore: ScopeStore, @unchecked Sendable {
    private let lock = NSLock()
    private var scopes: [ContainerScope]

    public init(scopes: [ContainerScope] = []) {
        self.scopes = scopes
    }

    public func load() -> [ContainerScope] {
        lock.lock()
        defer { lock.unlock() }
        return scopes
    }

    public func save(_ scopes: [ContainerScope]) {
        lock.lock()
        defer { lock.unlock() }
        self.scopes = scopes
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ScopeStoreTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CapsuleDomain/ScopeStore.swift Tests/CapsuleUnitTests/ScopeStoreTests.swift
git commit -m "feat(domain): ScopeStore seam + in-memory implementation

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Domain — `JSONPrettyPrinter` util

**Files:**
- Create: `Sources/CapsuleDomain/JSONPrettyPrinter.swift`
- Test: `Tests/CapsuleUnitTests/JSONPrettyPrinterTests.swift`

**Interfaces:**
- Produces: `enum JSONPrettyPrinter { static func prettyPrint(_ raw: String) -> String }` — pretty-prints valid JSON (sorted keys); returns the input unchanged when it is not valid JSON (the raw-payload fallback for the inspector).

- [ ] **Step 1: Write the failing test** — create `JSONPrettyPrinterTests.swift`:

```swift
//
//  JSONPrettyPrinterTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class JSONPrettyPrinterTests: XCTestCase {
    func testPrettyPrintsCompactJSON() {
        let out = JSONPrettyPrinter.prettyPrint(#"{"b":1,"a":2}"#)
        XCTAssertTrue(out.contains("\n"))
        // Sorted keys: "a" appears before "b".
        let a = out.range(of: "\"a\"")
        let b = out.range(of: "\"b\"")
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertTrue(a!.lowerBound < b!.lowerBound)
    }

    func testReturnsRawWhenNotJSON() {
        XCTAssertEqual(JSONPrettyPrinter.prettyPrint("not json"), "not json")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter JSONPrettyPrinterTests`
Expected: FAIL — type not defined.

- [ ] **Step 3: Implement.** Create `Sources/CapsuleDomain/JSONPrettyPrinter.swift`:

```swift
//
//  JSONPrettyPrinter.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`.

import Foundation

/// Formats a raw JSON string for display, falling back to the unmodified input when the
/// payload is not valid JSON — so a CLI schema drift degrades to "show the raw text"
/// rather than an empty inspector.
public enum JSONPrettyPrinter {
    public static func prettyPrint(_ raw: String) -> String {
        guard
            let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: pretty, encoding: .utf8)
        else {
            return raw
        }
        return string
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter JSONPrettyPrinterTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CapsuleDomain/JSONPrettyPrinter.swift Tests/CapsuleUnitTests/JSONPrettyPrinterTests.swift
git commit -m "feat(domain): JSONPrettyPrinter with raw fallback

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Domain — `ContainerBrowserModel` + `ContainerInspection`

**Files:**
- Create: `Sources/CapsuleDomain/ContainerBrowserModel.swift`
- Test: `Tests/CapsuleUnitTests/ContainerBrowserModelTests.swift`

**Interfaces:**
- Consumes: `ContainerBackend`, `MockBackend` (Task 1), `Container` (Task 3), `ContainerScope`/`ContainerStateFilter` (Task 4), `ScopeStore`/`InMemoryScopeStore` (Task 5), `CapsuleError`/`ErrorDetail`, `SystemStatusModel.defaultNormalize`.
- Produces `ContainerBrowserModel` (`@Observable @MainActor`) with:
  - `var searchText: String`, `var stateFilter: ContainerStateFilter`, `var selection: Set<Container.ID>`
  - `private(set) var allContainers: [Container]`, `private(set) var loadState: ContainerLoadState`, `private(set) var savedScopes: [ContainerScope]`
  - `var rows: [Container]` (filtered by `stateFilter` + `searchText`, sorted by name)
  - `var selectedContainers: [Container]`, `var isEmptyButHealthy: Bool`, `var noMatches: Bool`
  - `func refresh() async`, `func inspect(id: String) async -> ContainerInspection`
  - `func loadScopes()`, `func saveCurrentScope(name: String)`, `func removeScope(_ scope: ContainerScope)`, `func activate(_ scope: ContainerScope)`
- Plus `enum ContainerLoadState: Sendable, Equatable { case idle, loading, loaded, unavailable(ErrorDetail) }` and `struct ContainerInspection: Sendable, Equatable { var value: Container?; var rawJSON: String }`.

- [ ] **Step 1: Write the failing test** — create `ContainerBrowserModelTests.swift`:

```swift
//
//  ContainerBrowserModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class ContainerBrowserModelTests: XCTestCase {
    private func model(
        backend: any ContainerBackend = MockBackend(),
        store: any ScopeStore = InMemoryScopeStore()
    ) -> ContainerBrowserModel {
        ContainerBrowserModel(backend: backend, scopeStore: store)
    }

    func testRefreshLoadsAllContainers() async {
        let m = model()
        await m.refresh()
        XCTAssertEqual(m.loadState, .loaded)
        XCTAssertEqual(m.allContainers.count, 3)
    }

    func testStateFilterNarrowsRows() async {
        let m = model()
        await m.refresh()
        m.stateFilter = .running
        XCTAssertTrue(m.rows.allSatisfy { $0.state == .running })
        XCTAssertEqual(m.rows.count, 2)
    }

    func testSearchMatchesNameImageOrID() async {
        let m = model()
        await m.refresh()
        m.searchText = "postgres"
        XCTAssertEqual(m.rows.map(\.name), ["db"])
    }

    func testRowsAreSortedByName() async {
        let m = model()
        await m.refresh()
        XCTAssertEqual(m.rows.map(\.name), ["cache", "db", "web"])
    }

    func testNoMatchesIsDistinctFromEmptyButHealthy() async {
        let m = model()
        await m.refresh()
        m.searchText = "zzz-nothing"
        XCTAssertTrue(m.noMatches)
        XCTAssertFalse(m.isEmptyButHealthy)
    }

    func testEmptyButHealthyWhenServiceUpButNoContainers() async {
        let m = model(backend: MockBackend(containers: []))
        await m.refresh()
        XCTAssertTrue(m.isEmptyButHealthy)
        XCTAssertFalse(m.noMatches)
    }

    func testRefreshFailureRoutesToUnavailableNotEmpty() async {
        let backend = MockBackend()
        backend.failure = .executableNotFound("container")
        let m = model(backend: backend)
        await m.refresh()
        guard case .unavailable(let detail) = m.loadState else {
            return XCTFail("expected .unavailable, got \(m.loadState)")
        }
        XCTAssertFalse(detail.title.isEmpty)
        XCTAssertTrue(m.allContainers.isEmpty)
        XCTAssertFalse(m.isEmptyButHealthy)  // unavailable != empty-but-healthy
    }

    func testSelectionPrunedToExistingContainersOnRefresh() async {
        let m = model()
        await m.refresh()
        m.selection = ["a1b2c3d4", "ghost-id"]
        await m.refresh()
        XCTAssertEqual(m.selection, ["a1b2c3d4"])
    }

    func testInspectReturnsRawAndDecodedValue() async {
        let m = model()
        await m.refresh()
        let inspection = await m.inspect(id: "a1b2c3d4")
        XCTAssertEqual(inspection.value?.id, "a1b2c3d4")
        XCTAssertFalse(inspection.rawJSON.isEmpty)
    }

    func testSaveActivateAndRemoveScope() async {
        let store = InMemoryScopeStore()
        let m = model(store: store)
        m.stateFilter = .running
        m.searchText = "web"
        m.saveCurrentScope(name: "Web Running")
        XCTAssertEqual(m.savedScopes.count, 1)
        XCTAssertEqual(store.load().count, 1)  // persisted

        m.stateFilter = .all
        m.searchText = ""
        m.activate(m.savedScopes[0])
        XCTAssertEqual(m.stateFilter, .running)
        XCTAssertEqual(m.searchText, "web")

        m.removeScope(m.savedScopes[0])
        XCTAssertTrue(m.savedScopes.isEmpty)
        XCTAssertTrue(store.load().isEmpty)
    }

    func testLoadScopesReadsFromStore() {
        let store = InMemoryScopeStore(scopes: [
            ContainerScope(id: "1", name: "Seed", stateFilter: .stopped, searchTerm: "")
        ])
        let m = model(store: store)
        m.loadScopes()
        XCTAssertEqual(m.savedScopes.map(\.name), ["Seed"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ContainerBrowserModelTests`
Expected: FAIL — `ContainerBrowserModel` not defined.

- [ ] **Step 3: Implement.** Create `Sources/CapsuleDomain/ContainerBrowserModel.swift`:

```swift
//
//  ContainerBrowserModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The model is
//  `@Observable` (from `Observation`, not SwiftUI) so the UI can bind to it while the
//  domain stays UI-free. It maps the backend's raw `Parsed<ContainerSummary>` into the
//  domain `ContainerInspection` so no backend wire type reaches the UI.

import CapsuleBackend
import Foundation
import Observation

/// The load state of the container list, kept separate from the filtered `rows` so the UI
/// can distinguish "service unreachable" from "no containers" from "no matches".
public enum ContainerLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case unavailable(ErrorDetail)
}

/// A container inspection: the decoded domain value (nil if the payload drifted) paired
/// with the exact raw JSON, so the inspector can always show *something*.
public struct ContainerInspection: Sendable, Equatable {
    public var value: Container?
    public var rawJSON: String

    public init(value: Container?, rawJSON: String) {
        self.value = value
        self.rawJSON = rawJSON
    }
}

/// Owns the containers browser surface: the loaded list, the live query (search + state
/// filter), the multi-selection, and the user's saved scopes. Lifecycle actions are
/// Milestone 5B and deliberately absent here.
@MainActor
@Observable
public final class ContainerBrowserModel {
    public private(set) var allContainers: [Container] = []
    public private(set) var loadState: ContainerLoadState = .idle
    public private(set) var savedScopes: [ContainerScope] = []

    public var searchText: String = ""
    public var stateFilter: ContainerStateFilter = .all
    public var selection: Set<Container.ID> = []

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let scopeStore: any ScopeStore
    private let onActivity: @MainActor (String) -> Void

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        scopeStore: any ScopeStore = InMemoryScopeStore(),
        onActivity: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.backend = backend
        self.normalize = normalize
        self.scopeStore = scopeStore
        self.onActivity = onActivity
    }

    // MARK: Derived views

    /// Containers passing the active state filter and search term, sorted by name.
    public var rows: [Container] {
        allContainers
            .filter { stateFilter.matches($0.state) }
            .filter { matchesSearch($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public var selectedContainers: [Container] {
        allContainers.filter { selection.contains($0.id) }
    }

    /// The service is up but there are genuinely no containers (distinct from a down
    /// service and from a filter that matched nothing).
    public var isEmptyButHealthy: Bool {
        loadState == .loaded && allContainers.isEmpty
    }

    /// There are containers, but the active filter/search matched none.
    public var noMatches: Bool {
        loadState == .loaded && !allContainers.isEmpty && rows.isEmpty
    }

    private func matchesSearch(_ container: Container) -> Bool {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        return container.name.localizedCaseInsensitiveContains(term)
            || container.image.localizedCaseInsensitiveContains(term)
            || container.id.localizedCaseInsensitiveContains(term)
    }

    // MARK: Loading

    public func refresh() async {
        loadState = .loading
        do {
            let summaries = try await backend.listContainers(all: true)
            allContainers = summaries.map(Container.init(summary:))
            selection = selection.intersection(Set(allContainers.map(\.id)))
            loadState = .loaded
            onActivity("Loaded \(allContainers.count) container(s).")
        } catch {
            allContainers = []
            let detail = normalize(error).detail
            onActivity("Failed to load containers: \(detail.title)")
            loadState = .unavailable(detail)
        }
    }

    /// Inspects one container, mapping the backend's raw-retaining `Parsed` into the
    /// domain `ContainerInspection`. Never throws: a failure yields an empty raw payload.
    public func inspect(id: String) async -> ContainerInspection {
        do {
            let parsed = try await backend.inspectContainer(id: id)
            return ContainerInspection(
                value: parsed.value.map(Container.init(summary:)),
                rawJSON: parsed.raw
            )
        } catch {
            return ContainerInspection(value: nil, rawJSON: "")
        }
    }

    // MARK: Saved scopes

    public func loadScopes() {
        savedScopes = scopeStore.load()
    }

    public func saveCurrentScope(name: String) {
        let scope = ContainerScope(
            id: UUID().uuidString,
            name: name,
            stateFilter: stateFilter,
            searchTerm: searchText
        )
        savedScopes.append(scope)
        scopeStore.save(savedScopes)
        onActivity("Saved scope “\(name)”.")
    }

    public func removeScope(_ scope: ContainerScope) {
        savedScopes.removeAll { $0.id == scope.id }
        scopeStore.save(savedScopes)
    }

    /// Applies a scope's filter + search term to the live query.
    public func activate(_ scope: ContainerScope) {
        stateFilter = scope.stateFilter
        searchText = scope.searchTerm
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ContainerBrowserModelTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CapsuleDomain/ContainerBrowserModel.swift Tests/CapsuleUnitTests/ContainerBrowserModelTests.swift
git commit -m "feat(domain): ContainerBrowserModel (list, search, filter, scopes, inspect)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: UI — container state color

**Files:**
- Modify: `Sources/CapsuleUI/CapsuleColors.swift`
- Test: `Tests/CapsuleUnitTests/SidebarSectionTests.swift` (append; it already lives in the UI-facing test area) — or create `Tests/CapsuleUnitTests/CapsuleColorsTests.swift`.

**Interfaces:**
- Consumes: `ContainerState` (domain).
- Produces: `CapsuleColors.containerStateColor(_ state: ContainerState) -> Color`.

- [ ] **Step 1: Write the failing test** — create `Tests/CapsuleUnitTests/CapsuleColorsTests.swift`:

```swift
//
//  CapsuleColorsTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import SwiftUI
import XCTest

@testable import CapsuleUI

final class CapsuleColorsTests: XCTestCase {
    func testRunningAndStoppedHaveDistinctColors() {
        XCTAssertNotEqual(
            CapsuleColors.containerStateColor(.running),
            CapsuleColors.containerStateColor(.stopped))
    }

    func testRunningIsGreen() {
        XCTAssertEqual(CapsuleColors.containerStateColor(.running), .green)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CapsuleColorsTests`
Expected: FAIL — `containerStateColor` not defined.

- [ ] **Step 3: Implement.** Add to `CapsuleColors` (before the closing brace):

```swift
    /// The status-dot color for a container's lifecycle state.
    public static func containerStateColor(_ state: ContainerState) -> Color {
        switch state {
        case .running: return .green
        case .stopped: return .secondary
        case .paused: return .orange
        case .created: return .blue
        case .unknown: return .gray
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CapsuleColorsTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CapsuleUI/CapsuleColors.swift Tests/CapsuleUnitTests/CapsuleColorsTests.swift
git commit -m "feat(ui): semantic color for container lifecycle state

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: UI — `ContainerListView`

**Files:**
- Create: `Sources/CapsuleUI/ContainerListView.swift`

**Interfaces:**
- Consumes: `ContainerBrowserModel`, `ContainerLoadState`, `ContainerScope`, `ContainerStateFilter`, `CapsuleColors.containerStateColor` (Tasks 4–8).
- Produces: `struct ContainerListView: View { init(model: ContainerBrowserModel) }` — a `Table` with multi-select, `.searchable`, a state-filter `Picker`, and a saved-scopes `Menu`. Verified by build + inspection (filtering logic is already unit-tested in the model).

- [ ] **Step 1: Implement the view.** Create `Sources/CapsuleUI/ContainerListView.swift`:

```swift
//
//  ContainerListView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The containers content column: a Table backed by ContainerBrowserModel. Filtering and
//  scope logic live in the model (and are unit-tested there); this view is the thin
//  presentation + selection surface. Lifecycle actions arrive in Milestone 5B.

import CapsuleDomain
import SwiftUI

struct ContainerListView: View {
    @Bindable var model: ContainerBrowserModel

    @State private var showingSaveScope = false
    @State private var newScopeName = ""

    init(model: ContainerBrowserModel) {
        self.model = model
    }

    var body: some View {
        content
            .searchable(text: $model.searchText, prompt: "Search containers")
            .toolbar { toolbarContent }
            .task {
                model.loadScopes()
                await model.refresh()
            }
            .alert("Save Scope", isPresented: $showingSaveScope) {
                TextField("Scope name", text: $newScopeName)
                Button("Save") {
                    let name = newScopeName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { model.saveCurrentScope(name: name) }
                    newScopeName = ""
                }
                Button("Cancel", role: .cancel) { newScopeName = "" }
            } message: {
                Text("Saves the current filter and search as a reusable scope.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading:
            ProgressView("Loading containers…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let detail):
            ContentUnavailableView {
                Label(detail.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(detail.explanation)
            }
        case .loaded:
            if model.isEmptyButHealthy {
                ContentUnavailableView {
                    Label("No containers yet", systemImage: "shippingbox")
                } description: {
                    Text("Containers you create will appear here.")
                }
            } else {
                table
            }
        }
    }

    private var table: some View {
        Table(model.rows, selection: $model.selection) {
            TableColumn("") { container in
                Circle()
                    .fill(CapsuleColors.containerStateColor(container.state))
                    .frame(width: 8, height: 8)
                    .help(container.state.rawValue.capitalized)
            }
            .width(16)

            TableColumn("Name") { Text($0.name) }
            TableColumn("Image") { Text($0.image).foregroundStyle(.secondary) }
            TableColumn("IP") { container in
                Text(container.ip ?? "—").foregroundStyle(.secondary)
            }
            TableColumn("Created") { container in
                if let created = container.createdAt {
                    Text(created, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if model.noMatches {
                ContentUnavailableView.search
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Filter", selection: $model.stateFilter) {
                ForEach(ContainerStateFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .help("Filter containers by state")
        }

        ToolbarItem {
            Menu {
                ForEach(ContainerScope.builtIns) { scope in
                    Button(scope.name) { model.activate(scope) }
                }
                if !model.savedScopes.isEmpty {
                    Divider()
                    ForEach(model.savedScopes) { scope in
                        Button(scope.name) { model.activate(scope) }
                    }
                    Divider()
                    Menu("Remove Scope") {
                        ForEach(model.savedScopes) { scope in
                            Button(scope.name, role: .destructive) {
                                model.removeScope(scope)
                            }
                        }
                    }
                }
                Divider()
                Button("Save Current as Scope…") {
                    newScopeName = ""
                    showingSaveScope = true
                }
            } label: {
                Label("Scopes", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Saved scopes and views")
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `make build`
Expected: build succeeds, zero warnings.

- [ ] **Step 3: Commit**

```bash
git add Sources/CapsuleUI/ContainerListView.swift
git commit -m "feat(ui): ContainerListView — Table with search, filter, scopes, multi-select

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: UI — `ContainerInspectorView`

**Files:**
- Create: `Sources/CapsuleUI/ContainerInspectorView.swift`

**Interfaces:**
- Consumes: `ContainerBrowserModel`, `ContainerInspection`, `JSONPrettyPrinter` (Tasks 6–7), `CapsuleColors.containerStateColor`.
- Produces: `struct ContainerInspectorView: View { init(model: ContainerBrowserModel) }` — a `TabView` (Summary + Raw JSON) reflecting the current selection; Raw JSON is loaded via `model.inspect` and copyable. Verified by build + inspection.

- [ ] **Step 1: Implement the view.** Create `Sources/CapsuleUI/ContainerInspectorView.swift`:

```swift
//
//  ContainerInspectorView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The containers inspector: a friendly Summary tab plus a Raw JSON tab fed by
//  `container inspect`. The raw payload is always shown even when decoding drifts, and is
//  copyable. AppKit (NSPasteboard) is permitted in the UI layer.

import AppKit
import CapsuleDomain
import SwiftUI

struct ContainerInspectorView: View {
    let model: ContainerBrowserModel

    @State private var rawJSON = ""
    @State private var isLoadingRaw = false

    init(model: ContainerBrowserModel) {
        self.model = model
    }

    /// The single selected container, when exactly one row is selected.
    private var solo: Container? {
        guard model.selection.count == 1, let id = model.selection.first else { return nil }
        return model.selectedContainers.first { $0.id == id }
    }

    var body: some View {
        TabView {
            summaryTab
                .tabItem { Label("Summary", systemImage: "info.circle") }
            rawTab
                .tabItem { Label("Raw JSON", systemImage: "curlybraces") }
        }
        .task(id: model.selection) {
            await loadRaw()
        }
    }

    // MARK: Summary

    @ViewBuilder
    private var summaryTab: some View {
        if model.selection.isEmpty {
            ContentUnavailableView(
                "No Selection", systemImage: "shippingbox",
                description: Text("Select a container to see its details."))
        } else if let container = solo {
            Form {
                Section("Container") {
                    LabeledContent("Name", value: container.name)
                    LabeledContent("ID", value: container.shortID)
                    LabeledContent("Image", value: container.image)
                    LabeledContent("State") {
                        Label {
                            Text(container.state.rawValue.capitalized)
                        } icon: {
                            Circle()
                                .fill(CapsuleColors.containerStateColor(container.state))
                                .frame(width: 8, height: 8)
                        }
                    }
                    LabeledContent("IP", value: container.ip ?? "—")
                    if let created = container.createdAt {
                        LabeledContent("Created") {
                            Text(created, format: .dateTime)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "\(model.selection.count) Containers Selected",
                systemImage: "square.stack.3d.up",
                description: Text("Select a single container to see its details."))
        }
    }

    // MARK: Raw JSON

    @ViewBuilder
    private var rawTab: some View {
        if solo == nil {
            ContentUnavailableView(
                "No Selection", systemImage: "curlybraces",
                description: Text("Select a single container to inspect its raw JSON."))
        } else {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        copyRaw()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .disabled(rawJSON.isEmpty)
                }
                .padding(8)

                Divider()

                ScrollView([.vertical, .horizontal]) {
                    Text(rawJSON.isEmpty ? "No raw payload available." : rawJSON)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .overlay {
                    if isLoadingRaw { ProgressView() }
                }
            }
        }
    }

    // MARK: Actions

    private func loadRaw() async {
        guard let container = solo else {
            rawJSON = ""
            return
        }
        isLoadingRaw = true
        let inspection = await model.inspect(id: container.id)
        rawJSON = JSONPrettyPrinter.prettyPrint(inspection.rawJSON)
        isLoadingRaw = false
    }

    private func copyRaw() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(rawJSON, forType: .string)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `make build`
Expected: build succeeds, zero warnings.

- [ ] **Step 3: Commit**

```bash
git add Sources/CapsuleUI/ContainerInspectorView.swift
git commit -m "feat(ui): ContainerInspectorView — friendly summary + raw JSON tab

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11: UI — wire browser + inspector into the shell

**Files:**
- Modify: `Sources/CapsuleUI/ContentColumnView.swift`
- Modify: `Sources/CapsuleUI/AppShellView.swift`

**Interfaces:**
- Consumes: `ContainerListView` (Task 9), `ContainerInspectorView` (Task 10), `ContainerBrowserModel` (Task 7).
- Produces: `ContentColumnView` and `AppShellView` both gain a `browserModel: ContainerBrowserModel` parameter; the `.containers` section renders the live list, and the `.inspector` slot renders `ContainerInspectorView` for `.containers`.

- [ ] **Step 1: Update `ContentColumnView`.** Replace its stored properties + `body` so it takes the browser model and routes `.containers`:

```swift
struct ContentColumnView: View {
    let section: SidebarSection
    let health: SystemHealth
    let actions: ShellActions
    let browserModel: ContainerBrowserModel

    private var onRecover: (RecoveryAction) -> Void { actions.recover }

    var body: some View {
        Group {
            if section == .system {
                SystemDetailView(health: health, actions: actions)
            } else if health.isRunning {
                runningContent
            } else {
                healthState
            }
        }
        .navigationTitle(section.title)
    }

    @ViewBuilder
    private var runningContent: some View {
        if section == .containers {
            ContainerListView(model: browserModel)
        } else {
            resourcePlaceholder
        }
    }
```

Leave `resourcePlaceholder` and `healthState` unchanged below this point.

- [ ] **Step 2: Update `AppShellView`.** Add the stored property + init parameter:

```swift
public struct AppShellView: View {
    @Bindable var shell: ShellState
    let systemModel: SystemStatusModel
    let workspaceModel: WorkspaceModel
    let browserModel: ContainerBrowserModel
    let actions: ShellActions

    public init(
        shell: ShellState,
        systemModel: SystemStatusModel,
        workspaceModel: WorkspaceModel,
        browserModel: ContainerBrowserModel,
        actions: ShellActions
    ) {
        self.shell = shell
        self.systemModel = systemModel
        self.workspaceModel = workspaceModel
        self.browserModel = browserModel
        self.actions = actions
    }
```

In `detailColumn`, pass the model to `ContentColumnView`:

```swift
            ContentColumnView(
                section: shell.selection,
                health: systemModel.health,
                actions: actions,
                browserModel: browserModel
            )
```

And replace the `.inspector` modifier body to choose the containers inspector:

```swift
        .inspector(isPresented: $shell.inspectorPresented) {
            Group {
                if shell.selection == .containers {
                    ContainerInspectorView(model: browserModel)
                } else {
                    InspectorView(section: shell.selection)
                }
            }
            .inspectorColumnWidth(min: 240, ideal: 320, max: 420)
        }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `make build`
Expected: FAIL — `RootView` still calls `AppShellView(...)` without `browserModel`. (This is expected; Task 12 fixes the call sites. If you prefer a green build at every task, do Steps 1–3 of Task 12 before building.)

Proceed to Task 12 immediately; they compile together.

- [ ] **Step 4: Commit (with Task 12)** — commit this together with Task 12 so the tree builds. See Task 12 Step 5.

---

### Task 12: App — `UserDefaultsScopeStore` + composition wiring

**Files:**
- Create: `Sources/CapsuleApp/UserDefaultsScopeStore.swift`
- Modify: `Sources/CapsuleApp/AppEnvironment.swift`
- Modify: `Sources/CapsuleUI/RootView.swift`
- Modify: `Sources/CapsuleApp/CapsuleScene.swift`
- Test: `Tests/CapsuleUnitTests/CompositionTests.swift` (append)

**Interfaces:**
- Consumes: `ScopeStore` (Task 5), `ContainerBrowserModel` (Task 7), `AppShellView`/`RootView` updated signatures (Task 11), `ErrorNormalizer.normalize`.
- Produces: `struct UserDefaultsScopeStore: ScopeStore`; `AppEnvironment.browserModel`; `RootView` + `CapsuleScene` thread the browser model.

- [ ] **Step 1: Create `UserDefaultsScopeStore`.** `Sources/CapsuleApp/UserDefaultsScopeStore.swift`:

```swift
//
//  UserDefaultsScopeStore.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The concrete `ScopeStore` for saved container scopes. It lives in the composition root
//  (not the domain) so the persistence key and JSON encoding stay out of `CapsuleDomain`.

import CapsuleDomain
import Foundation

struct UserDefaultsScopeStore: ScopeStore {
    private let defaults: UserDefaults
    private let key = "capsule.containerScopes"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [ContainerScope] {
        guard
            let data = defaults.data(forKey: key),
            let scopes = try? JSONDecoder().decode([ContainerScope].self, from: data)
        else {
            return []
        }
        return scopes
    }

    func save(_ scopes: [ContainerScope]) {
        guard let data = try? JSONEncoder().encode(scopes) else { return }
        defaults.set(data, forKey: key)
    }
}
```

- [ ] **Step 2: Wire `AppEnvironment`.** Add the property, init param, and `live()` construction.

Add to the struct's stored properties (after `workspaceModel`):

```swift
    public var browserModel: ContainerBrowserModel
```

Add to the memberwise `init` parameter list (after `workspaceModel:`) and body:

```swift
        browserModel: ContainerBrowserModel,
```
```swift
        self.browserModel = browserModel
```

In `live()`, after `workspaceModel` is built, add:

```swift
        let browserModel = ContainerBrowserModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            scopeStore: UserDefaultsScopeStore(),
            onActivity: { line in shell.appendActivity(line) }
        )
```

and pass `browserModel: browserModel` in the returned `AppEnvironment(...)`.

- [ ] **Step 3: Wire `RootView`.** Add the stored property, init param, and pass-through.

Property (after `workspaceModel`):

```swift
    private let browserModel: ContainerBrowserModel
```

Init param (after `workspaceModel:`) and body assignment:

```swift
        browserModel: ContainerBrowserModel,
```
```swift
        self.browserModel = browserModel
```

In `body`, pass it to `AppShellView`:

```swift
        AppShellView(
            shell: shell,
            systemModel: systemModel,
            workspaceModel: workspaceModel,
            browserModel: browserModel,
            actions: actions
        )
```

- [ ] **Step 4: Wire `CapsuleScene`.** Add the `@State` and thread it.

Property (after `workspaceModel`):

```swift
    @State private var browserModel: ContainerBrowserModel
```

In `init(environment:)`:

```swift
        self._browserModel = State(initialValue: environment.browserModel)
```

In `body`, pass to `RootView`:

```swift
            RootView(
                shell: shell,
                systemModel: systemModel,
                workspaceModel: workspaceModel,
                browserModel: browserModel,
                actions: actions
            )
```

- [ ] **Step 5: Update the composition test.** Append to `CompositionTests.swift`:

```swift
    @MainActor
    func testLiveEnvironmentBuildsBrowserModel() {
        let env = AppEnvironment.live()
        XCTAssertEqual(env.browserModel.loadState, .idle)
        XCTAssertTrue(env.browserModel.allContainers.isEmpty)
    }
```

(If `CompositionTests` lacks `import CapsuleDomain`, add it.)

- [ ] **Step 6: Build + test**

Run: `make build` then `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CompositionTests`
Expected: build succeeds (zero warnings); CompositionTests PASS.

- [ ] **Step 7: Commit (Tasks 11 + 12 together)**

```bash
git add Sources/CapsuleApp Sources/CapsuleUI/RootView.swift Sources/CapsuleUI/ContentColumnView.swift Sources/CapsuleUI/AppShellView.swift Tests/CapsuleUnitTests/CompositionTests.swift
git commit -m "feat(app): wire containers browser + inspector into the shell

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 13: Verify the whole milestone green

**Files:** none (verification only).

- [ ] **Step 1: Run the full CI gate**

Run: `make ci`
Expected: PASS — zero-warning build, `swift-format --strict` clean, architecture guard holds (UI imports no Backend; Domain imports no UI/Process), license headers OK, all unit + integration tests green.

- [ ] **Step 2: If `swift-format` flags anything**

Run: `make format` then re-run `make ci`.

- [ ] **Step 3: Launch the app for a visual smoke check**

Run: `make app` (builds the Xcode target). Optionally `make run`.
Expected: app launches; with the service running, the Containers section shows the live `Table`; selecting a row populates the inspector Summary + Raw JSON; search/filter/scope menu function; daemon-down shows the health state (not an empty list). Visual pass is by inspection (consistent with Milestone 4).

- [ ] **Step 4: Final commit if `make format` changed anything**

```bash
git add -A
git commit -m "style: swift-format milestone 5A

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Live list from real JSON → Tasks 1–2 (CLI parse incl. `createdAt`), 7 (`refresh`), 9 (`Table`). ✔
- Search → Task 7 (`matchesSearch`) + 9 (`.searchable`). ✔
- Column/state filters → Task 4 (`ContainerStateFilter`) + 7 (`rows`) + 9 (`Picker`). ✔
- Saved scopes/views (persisted) → Tasks 4 (`ContainerScope`), 5 (`ScopeStore`), 7 (save/activate/remove/load), 9 (Menu), 12 (`UserDefaultsScopeStore`). ✔
- Multi-select + keyboard-navigable rows → Task 9 (`Table(selection:)`, native focus). ✔
- Inspector friendly summary + raw JSON tab + copy + raw fallback on drift → Tasks 6 (`JSONPrettyPrinter` fallback), 7 (`inspect`/`ContainerInspection` with optional `value`), 10 (`ContainerInspectorView`). ✔
- Daemon-down shows health, not empty; empty-but-healthy distinct → Task 7 (`loadState`/`isEmptyButHealthy`/`noMatches`), 9 (states), existing `ContentColumnView` health gate (Task 11). ✔
- Tested against `MockBackend` → Tasks 1, 7 (full suite). ✔
- Arch guard: no Backend type in a UI signature → `ContainerInspection` (domain) wraps `Parsed<ContainerSummary>` so UI never names a Backend type. ✔
- Out of scope (5B): no lifecycle/mutating port methods added. ✔

**Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to Task N"; every code step shows complete code. ✔

**Type consistency:** `ContainerBrowserModel` members (`rows`, `selection`, `stateFilter`, `searchText`, `loadState`, `savedScopes`, `inspect`→`ContainerInspection`, `saveCurrentScope`/`activate`/`removeScope`/`loadScopes`) are used identically in Tasks 9–12. `ContainerLoadState` cases (`idle`/`loading`/`loaded`/`unavailable`) match between Tasks 7 and 9. `CapsuleColors.containerStateColor` signature matches across Tasks 8–10. `AppShellView`/`RootView`/`CapsuleScene`/`AppEnvironment` all gain the same `browserModel: ContainerBrowserModel` label. ✔

**Note on Task 11 build:** Task 11's view edits and Task 12's call-site edits are interdependent; the plan builds them together (Task 12 Step 6) and commits them in one commit (Task 12 Step 7). This is the one place a single task does not end on a green build in isolation — by design, to avoid a broken intermediate API.
