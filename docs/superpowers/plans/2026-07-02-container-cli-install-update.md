# Container CLI Install & Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect a missing `container` CLI as a first-class state with an in-app "install latest signed release" flow, and add an Update container button (System ▸ About) that hands Apple's `/usr/local/bin/update-container.sh` to Terminal.

**Architecture:** A new `ContainerReleaseSource` port in `CapsuleBackend` (GitHub releases lookup + signed-pkg download) with a `URLSession` adapter in `CapsuleRegistryClient`; a `ContainerCLIUpdateModel` in `CapsuleDomain` that registers the download as a TaskCenter task and opens Installer.app via an injected closure; the update path reuses the existing `.command`-script Terminal handoff. `BackendError.executableNotFound` stops collapsing into `daemonUnavailable` and instead becomes `CapsuleError.cliNotInstalled` → `SystemHealth.notInstalled`.

**Tech Stack:** Swift 6 SPM package, SwiftUI, XCTest, `URLSession`, GitHub REST (`api.github.com/repos/apple/container/releases/latest`).

**Spec:** `docs/superpowers/specs/2026-07-02-container-cli-install-update-design.md`

## Global Constraints

- Every new file starts with the license header (`//\n//  <File>.swift\n//  Capsule\n//\n//  Copyright © 2026 Capsule. All rights reserved.\n//`) — pre-commit enforces it.
- `CapsuleUI` imports only `CapsuleDomain` (+SwiftUI); `CapsuleDomain` imports only `CapsuleBackend`/Foundation/Observation. The new port lives in `CapsuleBackend` precisely so Domain/UI never name the adapter module. **Do not write the adapter module's name in comments inside Domain/UI files** — the architecture guard greps substrings including comments.
- No new SPM targets, no new dependency edges; `Scripts/check-architecture.sh` and `Tests/CapsuleUnitTests/ArchitectureGuardTests.swift` must pass unchanged.
- Tests are XCTest (`final class …Tests: XCTestCase`), unit tests run via `make test`; single-file runs via `swift test --filter <ClassName>`.
- Signed packages only: asset names `container-installer-signed.pkg` then `container-<tag>-installer-signed.pkg`; never select an unsigned asset.
- Run `make format` before each commit; `make check && make test` must pass at the end of every task.
- Commit messages end with:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01JYNmieH7AYvXys56bV8B7p`

---

### Task 1: Error currency — `RecoveryAction.installContainerCLI` + `CapsuleError.cliNotInstalled`

**Files:**
- Modify: `Sources/CapsuleDomain/CapsuleError.swift` (add enum cases + title)
- Modify: `Sources/CapsuleDomain/ErrorDetail.swift` (add `detail` + `status` arms)
- Test: `Tests/CapsuleUnitTests/CapsuleErrorTests.swift`

**Interfaces:**
- Produces: `RecoveryAction.installContainerCLI` (title `"Install container…"`), `CapsuleError.cliNotInstalled(message: String, recovery: [RecoveryAction])`, whose `.detail` is `ErrorDetail(title: "Container CLI not installed", explanation: message, recoveryActions: recovery.isEmpty ? [.installContainerCLI, .openLogs] : recovery)` and whose `.status` is `.backendUnavailable`.

- [ ] **Step 1: Write the failing tests** — append to `CapsuleErrorTests`:

```swift
func testInstallContainerCLIRecoveryHasTitle() {
    XCTAssertEqual(RecoveryAction.installContainerCLI.title, "Install container…")
}

func testCLINotInstalledDetailOffersInstall() {
    let error = CapsuleError.cliNotInstalled(
        message: "The container CLI could not be found at /usr/local/bin/container.",
        recovery: [.installContainerCLI, .openLogs])
    XCTAssertEqual(error.detail.title, "Container CLI not installed")
    XCTAssertEqual(
        error.detail.explanation,
        "The container CLI could not be found at /usr/local/bin/container.")
    XCTAssertEqual(error.detail.recoveryActions, [.installContainerCLI, .openLogs])
    XCTAssertEqual(error.status, .backendUnavailable)
}

func testCLINotInstalledDetailDefaultsRecovery() {
    let error = CapsuleError.cliNotInstalled(message: "missing", recovery: [])
    XCTAssertEqual(error.detail.recoveryActions, [.installContainerCLI, .openLogs])
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter CapsuleErrorTests` → FAIL: `installContainerCLI` / `cliNotInstalled` not members.
- [ ] **Step 3: Implement.** In `CapsuleError.swift`, add to `RecoveryAction` (after `.startServices`):

```swift
    /// Download and install the container CLI (missing-binary recovery).
    case installContainerCLI
```

and to its `title` switch: `case .installContainerCLI: return "Install container…"`. Add to `CapsuleError` (after `.daemonUnavailable`):

```swift
    /// The `container` CLI binary itself is not installed (distinct from an
    /// installed-but-unreachable service, so the UI can offer installation).
    case cliNotInstalled(message: String, recovery: [RecoveryAction])
```

In `ErrorDetail.swift`, add to the `detail` switch (after the `.daemonUnavailable` arm):

```swift
        case let .cliNotInstalled(message, recovery):
            return ErrorDetail(
                title: "Container CLI not installed",
                explanation: message,
                recoveryActions: recovery.isEmpty ? [.installContainerCLI, .openLogs] : recovery
            )
```

and to the `status` switch: change `case .daemonUnavailable:` to `case .daemonUnavailable, .cliNotInstalled:`.

- [ ] **Step 4: Fix exhaustive switches over `RecoveryAction`** — `swift build` now fails in `Sources/CapsuleApp/AppEnvironment.swift` (`makeActions`'s `recover` switch, around line 430). Bridge it temporarily by widening the existing fallback arm — change `case .editConfiguration, .grantPermission:` to `case .editConfiguration, .grantPermission, .installContainerCLI:` (Task 7 gives `.installContainerCLI` its real handler). Fix any other switch the compiler flags the same way.
- [ ] **Step 5: Verify** — `swift test --filter CapsuleErrorTests` → PASS, and `swift build` clean.
- [ ] **Step 6: Commit** — `feat(domain): add cliNotInstalled error + Install container recovery action`

---

### Task 2: Normalizer maps `executableNotFound` → `cliNotInstalled`

**Files:**
- Modify: `Sources/CapsuleDiagnostics/ErrorNormalization.swift:73-77`
- Test: `Tests/CapsuleUnitTests/ErrorNormalizerTests.swift:95-103` (rewrite the existing case)

**Interfaces:**
- Consumes: Task 1's `CapsuleError.cliNotInstalled`.
- Produces: `ErrorNormalizer.normalize(BackendError.executableNotFound(path))` → `.cliNotInstalled(message: "The container CLI could not be found at \(path).", recovery: [.installContainerCLI, .openLogs])`.

- [ ] **Step 1: Rewrite the existing test** `testExecutableNotFoundBecomesDaemonUnavailable` as:

```swift
    func testExecutableNotFoundBecomesCLINotInstalled() {
        let error = BackendError.executableNotFound("/usr/local/bin/container")
        guard case let .cliNotInstalled(message, recovery) = ErrorNormalizer.normalize(error)
        else {
            return XCTFail("expected .cliNotInstalled")
        }
        XCTAssertTrue(message.contains("/usr/local/bin/container"))
        XCTAssertEqual(recovery, [.installContainerCLI, .openLogs])
    }
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter ErrorNormalizerTests` → FAIL (still `.daemonUnavailable`).
- [ ] **Step 3: Implement** — replace the `.executableNotFound` arm in `normalizeBackendError`:

```swift
        case let .executableNotFound(path):
            return .cliNotInstalled(
                message: "The container CLI could not be found at \(path).",
                recovery: [.installContainerCLI, .openLogs]
            )
```

- [ ] **Step 4: Verify** — `swift test --filter ErrorNormalizerTests` → PASS. Run `make test`; fix any test elsewhere that asserted the old mapping.
- [ ] **Step 5: Commit** — `feat(diagnostics): normalize a missing CLI binary to cliNotInstalled`

---

### Task 3: `SystemHealth.notInstalled` + probe routing + presentation arms

**Files:**
- Modify: `Sources/CapsuleDomain/SystemHealth.swift` (new case + `bannerKind`/`statusLabel` arms)
- Modify: `Sources/CapsuleDomain/SystemStatusModel.swift:77-81` (route `.cliNotInstalled`)
- Modify: `Sources/CapsuleUI/SystemHealthBanner.swift:88-127` (bannerText + recoveryActions arms)
- Modify: `Sources/CapsuleUI/LocalizedDisplay.swift:74-81` (localizedStatusLabel arm)
- Modify: `Sources/CapsuleUI/OnboardingView.swift` (install branch + card copy)
- Test: `Tests/CapsuleUnitTests/SystemHealthTests.swift`, `Tests/CapsuleUnitTests/SystemStatusModelTests.swift`, `Tests/CapsuleUnitTests/BannerPresentationTests.swift`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: `SystemHealth.notInstalled(ErrorDetail)` — `bannerKind == .unhealthy`, `statusLabel == "Not Installed"`, `isRunning == false`. `SystemStatusModel.refreshStatus()` sets it whenever the normalized probe error is `.cliNotInstalled`. `OnboardingView` shows an **Install container…** button (`accessibilityIdentifier("onboarding-install-cli")`) that calls `actions.recover(.installContainerCLI)` plus a **Check Again** button calling `actions.recover(.retry)`.

- [ ] **Step 1: Write failing tests.** `SystemHealthTests`:

```swift
    func testNotInstalledPresentation() {
        let health = SystemHealth.notInstalled(
            ErrorDetail(title: "Container CLI not installed", explanation: "missing"))
        XCTAssertFalse(health.isRunning)
        XCTAssertEqual(health.bannerKind, .unhealthy)
        XCTAssertEqual(health.statusLabel, "Not Installed")
        XCTAssertTrue(health.availableFeatures.isEmpty)
    }
```

`SystemStatusModelTests` (mirror the existing unavailable-probe test's structure — MockBackend + `ErrorNormalizer.normalize` injected):

```swift
    func testMissingExecutableProbesToNotInstalled() async {
        let backend = MockBackend()
        backend.failure = .executableNotFound("/usr/local/bin/container")
        let model = SystemStatusModel(
            backend: backend, normalize: { ErrorNormalizer.normalize($0) })
        await model.refreshStatus()
        guard case let .notInstalled(detail) = model.health else {
            return XCTFail("expected .notInstalled, got \(model.health)")
        }
        XCTAssertTrue(detail.recoveryActions.contains(.installContainerCLI))
    }
```

(`SystemStatusModelTests` must `import CapsuleDiagnostics` if it doesn't already.) `BannerPresentationTests`:

```swift
    func testNotInstalledBannerOffersInstall() {
        let detail = ErrorDetail(
            title: "Container CLI not installed",
            explanation: "The container CLI could not be found at /usr/local/bin/container.",
            recoveryActions: [.installContainerCLI, .openLogs])
        let text = SystemHealthBanner.bannerText(for: .notInstalled(detail), warning: nil)
        XCTAssertEqual(text.title, "Container CLI not installed")
        XCTAssertEqual(text.kind, .unhealthy)
        XCTAssertEqual(
            SystemHealthBanner.recoveryActions(for: .notInstalled(detail)),
            [.installContainerCLI, .openLogs])
    }
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter SystemHealthTests` → FAIL (no `.notInstalled`).
- [ ] **Step 3: Implement.** `SystemHealth.swift` — add after `.unavailable`:

```swift
    /// The `container` CLI binary itself is not installed; carries a presentation-ready
    /// detail whose recovery actions offer installation.
    case notInstalled(ErrorDetail)
```

`bannerKind`: `case .stopped, .unavailable, .notInstalled: return .unhealthy`. `statusLabel`: `case .notInstalled: return "Not Installed"`. `SystemStatusModel.refreshStatus()` catch block becomes:

```swift
        } catch {
            let normalized = normalize(error)
            let detail = normalized.detail
            onActivity("System unavailable: \(detail.title)")
            if case .cliNotInstalled = normalized {
                health = .notInstalled(detail)
            } else {
                health = .unavailable(detail)
            }
        }
```

`SystemHealthBanner.bannerText` — add after the `.unavailable` arm:

```swift
        case let .notInstalled(detail):
            return BannerText(title: detail.title, message: detail.explanation, kind: .unhealthy)
```

`recoveryActions`: `case let .notInstalled(detail): return detail.recoveryActions`. `LocalizedDisplay.swift` `localizedStatusLabel`: `case .notInstalled: return uiString("Not Installed")`. `OnboardingView` — replace the non-running button group and card copy:

```swift
                } else if case .notInstalled = health {
                    Button("Install container…") { actions.recover(.installContainerCLI) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("onboarding-install-cli")
                    Button("Check Again") { actions.recover(.retry) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    Button("Continue", action: onFinish)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                } else {
```

and in `cardTitle` / `cardMessage`:

```swift
    private var cardTitle: String {
        if case .notInstalled = health { return "The container CLI is not installed" }
        return health.isRunning
            ? "Container services are running" : "Container services are not running"
    }

    private var cardMessage: String {
        if case let .running(version, _) = health {
            return "Connected to container \(version.client)."
        }
        if case .notInstalled = health {
            return "Capsule can download and install the latest signed release from GitHub."
        }
        return "Start the service now, or do it later from the System section."
    }
```

- [ ] **Step 4: Build & fix remaining exhaustive switches** — `swift build` and let the compiler list any other `switch` over `SystemHealth`; give each a `.notInstalled` arm following its `.unavailable` sibling. Then `swift test --filter 'SystemHealthTests|SystemStatusModelTests|BannerPresentationTests'` → PASS, and `make test` green.
- [ ] **Step 5: Commit** — `feat(domain,ui): first-class "CLI not installed" health state with install recovery`

---

### Task 4: Release port, asset selection, errors, mock (+ normalizer mapping)

**Files:**
- Create: `Sources/CapsuleBackend/ContainerCLIRelease.swift`
- Create: `Sources/CapsuleBackend/MockContainerReleaseSource.swift`
- Modify: `Sources/CapsuleDiagnostics/ErrorNormalization.swift` (release-error mapping)
- Test: `Tests/CapsuleUnitTests/ContainerCLIReleaseTests.swift` (new), `Tests/CapsuleUnitTests/ErrorNormalizerTests.swift`

**Interfaces:**
- Produces (all `public`, in `CapsuleBackend`):

```swift
public struct ContainerCLIReleaseAsset: Sendable, Equatable, Codable {
    public var name: String
    public var downloadURL: String
    public init(name: String, downloadURL: String)
}
public struct ContainerCLIRelease: Sendable, Equatable, Codable {
    public var tag: String
    public var assets: [ContainerCLIReleaseAsset]
    public init(tag: String, assets: [ContainerCLIReleaseAsset])
    public var signedInstallerAsset: ContainerCLIReleaseAsset? { get }
}
public enum ContainerReleaseError: Error, Sendable, Equatable {
    case rateLimited(retryAfterSeconds: Int?)
    case httpStatus(code: Int, message: String?)
    case network(message: String)
    case decodingFailed(String)
    case noSignedPackage(tag: String)
}
public protocol ContainerReleaseSource: Sendable {
    func latestRelease() async throws -> ContainerCLIRelease
    func downloadPackage(_ asset: ContainerCLIReleaseAsset, to destination: URL)
        -> AsyncThrowingStream<OutputLine, Error>
}
public final class MockContainerReleaseSource: ContainerReleaseSource, @unchecked Sendable
```

- [ ] **Step 1: Write failing tests** — `ContainerCLIReleaseTests.swift`:

```swift
//
//  ContainerCLIReleaseTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleBackend

final class ContainerCLIReleaseTests: XCTestCase {
    private func asset(_ name: String) -> ContainerCLIReleaseAsset {
        ContainerCLIReleaseAsset(name: name, downloadURL: "https://example.com/\(name)")
    }

    func testPrefersUnversionedSignedPackage() {
        let release = ContainerCLIRelease(
            tag: "1.0.0",
            assets: [
                asset("container-1.0.0-installer-signed.pkg"),
                asset("container-installer-signed.pkg"),
            ])
        XCTAssertEqual(release.signedInstallerAsset?.name, "container-installer-signed.pkg")
    }

    func testFallsBackToVersionedSignedPackage() {
        let release = ContainerCLIRelease(
            tag: "1.0.0",
            assets: [
                asset("container-dSYM.zip"),
                asset("container-installer-unsigned.pkg"),
                asset("container-1.0.0-installer-signed.pkg"),
            ])
        XCTAssertEqual(
            release.signedInstallerAsset?.name, "container-1.0.0-installer-signed.pkg")
    }

    func testNeverSelectsUnsignedPackage() {
        let release = ContainerCLIRelease(
            tag: "1.0.0",
            assets: [asset("container-installer-unsigned.pkg"), asset("container-dSYM.zip")])
        XCTAssertNil(release.signedInstallerAsset)
    }

    func testMockStreamsSeededLinesAndWritesDestination() async throws {
        let mock = MockContainerReleaseSource()
        let release = try await mock.latestRelease()
        XCTAssertEqual(release.tag, "1.2.3")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("capsule-test-\(UUID().uuidString).pkg")
        defer { try? FileManager.default.removeItem(at: destination) }
        var lines: [String] = []
        let signed = try XCTUnwrap(release.signedInstallerAsset)
        for try await line in mock.downloadPackage(signed, to: destination) {
            lines.append(line.text)
        }
        XCTAssertEqual(lines.last, "100%")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(mock.lastDownloadedAsset?.name, signed.name)
    }

    func testMockFailurePropagates() async {
        let mock = MockContainerReleaseSource()
        mock.failure = .network(message: "offline")
        do {
            _ = try await mock.latestRelease()
            XCTFail("expected a throw")
        } catch let error as ContainerReleaseError {
            XCTAssertEqual(error, .network(message: "offline"))
        } catch { XCTFail("unexpected error \(error)") }
    }
}
```

And in `ErrorNormalizerTests`:

```swift
    func testReleaseErrorsBecomeReadableUnknowns() {
        guard
            case let .unknown(message) = ErrorNormalizer.normalize(
                ContainerReleaseError.noSignedPackage(tag: "1.0.0"))
        else { return XCTFail("expected .unknown") }
        XCTAssertTrue(message.contains("1.0.0"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("signed"))
    }
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter ContainerCLIReleaseTests` → FAIL (types missing).
- [ ] **Step 3: Implement.** `ContainerCLIRelease.swift` (license header, then):

```swift
//  The container-CLI release port: looking up apple/container's latest GitHub release and
//  downloading its signed installer package. Deliberately a separate protocol from
//  `ContainerBackend` — installing/updating the CLI cannot be done by running the CLI —
//  and from the registry-search port, which speaks an image registry's catalog API.

import Foundation

public struct ContainerCLIReleaseAsset: Sendable, Equatable, Codable {
    public var name: String
    public var downloadURL: String

    public init(name: String, downloadURL: String) {
        self.name = name
        self.downloadURL = downloadURL
    }
}

public struct ContainerCLIRelease: Sendable, Equatable, Codable {
    public var tag: String
    public var assets: [ContainerCLIReleaseAsset]

    public init(tag: String, assets: [ContainerCLIReleaseAsset]) {
        self.tag = tag
        self.assets = assets
    }

    /// The signed installer package to install, or nil when the release carries none.
    /// Releases publish either `container-installer-signed.pkg` or the versioned
    /// `container-<tag>-installer-signed.pkg` (1.0.0 uses the latter); unsigned packages
    /// are never selected.
    public var signedInstallerAsset: ContainerCLIReleaseAsset? {
        assets.first { $0.name == "container-installer-signed.pkg" }
            ?? assets.first { $0.name == "container-\(tag)-installer-signed.pkg" }
    }
}

/// Errors a release-source adapter may surface. `rateLimited` stands apart so a 429 can
/// become a cooldown message rather than a retry loop; `noSignedPackage` is thrown by
/// callers when ``ContainerCLIRelease/signedInstallerAsset`` is nil.
public enum ContainerReleaseError: Error, Sendable, Equatable {
    case rateLimited(retryAfterSeconds: Int?)
    case httpStatus(code: Int, message: String?)
    case network(message: String)
    case decodingFailed(String)
    case noSignedPackage(tag: String)
}

/// Looks up and downloads apple/container releases.
public protocol ContainerReleaseSource: Sendable {
    /// The latest published release (tag + downloadable assets).
    func latestRelease() async throws -> ContainerCLIRelease

    /// Downloads `asset` to `destination`, yielding human-readable progress lines
    /// (`NN%` tokens drive determinate task progress). The stream finishing without a
    /// throw means `destination` holds the complete package; cancellation and failures
    /// remove the partial file.
    func downloadPackage(_ asset: ContainerCLIReleaseAsset, to destination: URL)
        -> AsyncThrowingStream<OutputLine, Error>
}
```

`MockContainerReleaseSource.swift` (license header, then):

```swift
//  The in-memory release source for tests, previews, and the golden-UI-test mode:
//  seedable release, scripted progress lines, recorded download calls, optional failure.

import Foundation

public final class MockContainerReleaseSource: ContainerReleaseSource, @unchecked Sendable {
    private let lock = NSLock()
    private var releaseValue: ContainerCLIRelease
    private var failureValue: ContainerReleaseError?
    private var lastDownloadedAssetValue: ContainerCLIReleaseAsset?

    public init(
        release: ContainerCLIRelease = ContainerCLIRelease(
            tag: "1.2.3",
            assets: [
                ContainerCLIReleaseAsset(
                    name: "container-installer-signed.pkg",
                    downloadURL: "https://example.com/container-installer-signed.pkg")
            ])
    ) {
        self.releaseValue = release
    }

    /// When set, `latestRelease` and `downloadPackage` fail with this error.
    public var failure: ContainerReleaseError? {
        get { lock.withLock { failureValue } }
        set { lock.withLock { failureValue = newValue } }
    }

    /// The asset passed to the most recent `downloadPackage` call.
    public var lastDownloadedAsset: ContainerCLIReleaseAsset? {
        lock.withLock { lastDownloadedAssetValue }
    }

    public func latestRelease() async throws -> ContainerCLIRelease {
        try lock.withLock {
            if let failureValue { throw failureValue }
            return releaseValue
        }
    }

    public func downloadPackage(
        _ asset: ContainerCLIReleaseAsset, to destination: URL
    ) -> AsyncThrowingStream<OutputLine, Error> {
        let failure = lock.withLock { failureValue }
        lock.withLock { lastDownloadedAssetValue = asset }
        return AsyncThrowingStream { continuation in
            if let failure {
                continuation.finish(throwing: failure)
                return
            }
            for percent in [25, 50, 75, 100] {
                continuation.yield(OutputLine(source: .stdout, text: "\(percent)%"))
            }
            FileManager.default.createFile(atPath: destination.path, contents: Data())
            continuation.finish()
        }
    }
}
```

`ErrorNormalization.swift` — in `normalize(_:)`, after the `BackendError` branch:

```swift
        if let release = error as? ContainerReleaseError {
            return normalizeReleaseError(release)
        }
```

and add the private helper:

```swift
    /// Maps release-source failures (GitHub lookup/download) into readable messages. These
    /// surface on the install task / About pane, so they favor plain language over codes.
    private static func normalizeReleaseError(_ error: ContainerReleaseError) -> CapsuleError {
        switch error {
        case let .rateLimited(retryAfterSeconds):
            let hint = retryAfterSeconds.map { " Try again in \($0)s." } ?? " Try again later."
            return .unknown(message: "GitHub is rate-limiting release requests.\(hint)")
        case let .httpStatus(code, message):
            return .unknown(
                message: message ?? "GitHub returned HTTP \(code) for the release request.")
        case let .network(message):
            return .unknown(message: "Could not reach GitHub: \(message)")
        case let .decodingFailed(message):
            return .unknown(message: "Could not decode the GitHub release: \(message)")
        case let .noSignedPackage(tag):
            return .unknown(
                message: "Release \(tag) does not include a signed installer package yet. "
                    + "Try again once it is published.")
        }
    }
```

- [ ] **Step 4: Verify** — `swift test --filter 'ContainerCLIReleaseTests|ErrorNormalizerTests'` → PASS.
- [ ] **Step 5: Commit** — `feat(backend): container CLI release port with signed-asset selection + mock`

---

### Task 5: `GitHubReleaseClient` adapter

**Files:**
- Create: `Sources/CapsuleRegistryClient/GitHubReleaseClient.swift`
- Test: `Tests/CapsuleUnitTests/GitHubReleaseClientTests.swift`

**Interfaces:**
- Consumes: Task 4's port; the module's internal `HTTPDataFetching` seam + `StubHTTPDataFetcher` test double (used by `DockerHubClientTests` — find it under `Tests/CapsuleUnitTests` and reuse; extend the stub only if it lacks a needed hook).
- Produces: `public struct GitHubReleaseClient: ContainerReleaseSource` with `public init()` and internal `init(fetcher:session:)`.

- [ ] **Step 1: Write failing tests** — `GitHubReleaseClientTests.swift` (mirror `DockerHubClientTests`'s stub usage; seed JSON inline, not fixtures):

```swift
//
//  GitHubReleaseClientTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import Foundation
import XCTest

@testable import CapsuleRegistryClient

final class GitHubReleaseClientTests: XCTestCase {
    private var fetcher: StubHTTPDataFetcher!
    private var client: GitHubReleaseClient!

    override func setUp() {
        super.setUp()
        fetcher = StubHTTPDataFetcher()
        client = GitHubReleaseClient(fetcher: fetcher)
    }

    private static let releaseJSON = Data(
        """
        {
          "tag_name": "1.0.0",
          "assets": [
            {"name": "container-1.0.0-installer-signed.pkg",
             "browser_download_url": "https://github.com/apple/container/releases/download/1.0.0/container-1.0.0-installer-signed.pkg",
             "unexpected_field": 7},
            {"name": "container-installer-unsigned.pkg",
             "browser_download_url": "https://github.com/apple/container/releases/download/1.0.0/container-installer-unsigned.pkg"}
          ],
          "prerelease": false
        }
        """.utf8)

    func testLatestReleaseBuildsExactURLAndDecodes() async throws {
        fetcher.seed(Self.releaseJSON)

        let release = try await client.latestRelease()

        let request = try XCTUnwrap(fetcher.request(withURLContaining: "releases/latest"))
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.github.com/repos/apple/container/releases/latest")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(release.tag, "1.0.0")
        XCTAssertEqual(release.assets.count, 2)
        XCTAssertEqual(
            release.signedInstallerAsset?.name, "container-1.0.0-installer-signed.pkg")
    }

    func testRateLimitMapsToRateLimited() async {
        fetcher.seed(
            Data(), statusCode: 429, headers: ["Retry-After": "30"])
        do {
            _ = try await client.latestRelease()
            XCTFail("expected a throw")
        } catch let error as ContainerReleaseError {
            XCTAssertEqual(error, .rateLimited(retryAfterSeconds: 30))
        } catch { XCTFail("unexpected error \(error)") }
    }

    func testHTTPFailureMapsToHTTPStatus() async {
        fetcher.seed(Data("{}".utf8), statusCode: 500)
        do {
            _ = try await client.latestRelease()
            XCTFail("expected a throw")
        } catch let error as ContainerReleaseError {
            guard case .httpStatus(code: 500, message: _) = error else {
                return XCTFail("expected .httpStatus(500), got \(error)")
            }
        } catch { XCTFail("unexpected error \(error)") }
    }

    func testGarbageBodyMapsToDecodingFailed() async {
        fetcher.seed(Data("not json".utf8))
        do {
            _ = try await client.latestRelease()
            XCTFail("expected a throw")
        } catch let error as ContainerReleaseError {
            guard case .decodingFailed = error else {
                return XCTFail("expected .decodingFailed, got \(error)")
            }
        } catch { XCTFail("unexpected error \(error)") }
    }
}
```

If `StubHTTPDataFetcher.seed` lacks `statusCode:`/`headers:` parameters, extend the stub with defaulted parameters (default 200 / `[:]`) so existing call sites compile unchanged.

- [ ] **Step 2: Run to verify failure** — `swift test --filter GitHubReleaseClientTests` → FAIL (type missing).
- [ ] **Step 3: Implement** — `GitHubReleaseClient.swift` (license header, then):

```swift
//  The apple/container GitHub-releases adapter, conforming to the backend's
//  `ContainerReleaseSource` port. Release lookup goes through the same `HTTPDataFetching`
//  seam as the Docker Hub adapter (stub-testable); the large package download streams
//  through `URLSession.bytes` directly, yielding `NN%` progress lines.

import CapsuleBackend
import Foundation

public struct GitHubReleaseClient: ContainerReleaseSource {
    private let fetcher: any HTTPDataFetching
    private let session: URLSession

    public init() {
        self.init(fetcher: URLSessionDataFetcher())
    }

    /// The seam init used by tests to record requests and replay canned responses.
    init(fetcher: any HTTPDataFetching, session: URLSession = .shared) {
        self.fetcher = fetcher
        self.session = session
    }

    public func latestRelease() async throws -> ContainerCLIRelease {
        let url = URL(string: "https://api.github.com/repos/apple/container/releases/latest")!
        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Capsule (macOS)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await fetcher.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw ContainerReleaseError.network(message: error.localizedDescription)
        } catch let error as ContainerReleaseError {
            throw error
        } catch {
            throw ContainerReleaseError.network(message: String(describing: error))
        }

        switch response.statusCode {
        case 200..<300:
            break
        case 403, 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Int($0) }
            throw ContainerReleaseError.rateLimited(retryAfterSeconds: retryAfter)
        default:
            throw ContainerReleaseError.httpStatus(
                code: response.statusCode, message: Self.errorMessage(in: data))
        }

        let wire: GitHubRelease
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            wire = try decoder.decode(GitHubRelease.self, from: data)
        } catch {
            throw ContainerReleaseError.decodingFailed(String(describing: error))
        }
        guard let tag = wire.tagName, !tag.isEmpty else {
            throw ContainerReleaseError.decodingFailed("release JSON carries no tag_name")
        }
        let assets = (wire.assets ?? []).compactMap { asset -> ContainerCLIReleaseAsset? in
            guard let name = asset.name, let url = asset.browserDownloadUrl else { return nil }
            return ContainerCLIReleaseAsset(name: name, downloadURL: url)
        }
        return ContainerCLIRelease(tag: tag, assets: assets)
    }

    public func downloadPackage(
        _ asset: ContainerCLIReleaseAsset, to destination: URL
    ) -> AsyncThrowingStream<OutputLine, Error> {
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: asset.downloadURL) else {
                        throw ContainerReleaseError.network(
                            message: "Invalid download URL for \(asset.name).")
                    }
                    var request = URLRequest(url: url)
                    request.setValue("Capsule (macOS)", forHTTPHeaderField: "User-Agent")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                        (200..<300).contains(http.statusCode)
                    else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw ContainerReleaseError.httpStatus(code: code, message: nil)
                    }
                    continuation.yield(
                        OutputLine(source: .stdout, text: "Downloading \(asset.name)…"))
                    let total = response.expectedContentLength
                    FileManager.default.createFile(atPath: destination.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: destination)
                    defer { try? handle.close() }
                    var buffer = Data()
                    buffer.reserveCapacity(1 << 16)
                    var written: Int64 = 0
                    var lastPercent = -1
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= 1 << 16 {
                            try handle.write(contentsOf: buffer)
                            written += Int64(buffer.count)
                            buffer.removeAll(keepingCapacity: true)
                            if total > 0 {
                                let percent = Int(written * 100 / total)
                                if percent != lastPercent {
                                    lastPercent = percent
                                    continuation.yield(
                                        OutputLine(source: .stdout, text: "\(percent)%"))
                                }
                            }
                        }
                    }
                    if !buffer.isEmpty {
                        try handle.write(contentsOf: buffer)
                        written += Int64(buffer.count)
                    }
                    continuation.yield(
                        OutputLine(
                            source: .stdout,
                            text: "Downloaded \(asset.name) (\(written) bytes)."))
                    continuation.finish()
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// GitHub error bodies carry a short `message` field; surface it when present.
    private static func errorMessage(in data: Data) -> String? {
        struct Body: Decodable { var message: String? }
        return (try? JSONDecoder().decode(Body.self, from: data))?.message
    }
}

// MARK: - Wire types (api.github.com)

private struct GitHubRelease: Decodable {
    var tagName: String?
    var assets: [GitHubAsset]?
}

private struct GitHubAsset: Decodable {
    var name: String?
    var browserDownloadUrl: String?
}
```

- [ ] **Step 4: Verify** — `swift test --filter GitHubReleaseClientTests` → PASS; `make test` green (DockerHub stub extension must not break its tests).
- [ ] **Step 5: Commit** — `feat(registryclient): GitHub release adapter for apple/container`

---

### Task 6: `ContainerCLIUpdateModel` + `OperationKind.cliInstall`

**Files:**
- Create: `Sources/CapsuleDomain/ContainerCLIUpdateModel.swift`
- Modify: `Sources/CapsuleDomain/TaskCenter.swift:17-61` (enum case + arms)
- Modify: `Sources/CapsuleUI/LocalizedDisplay.swift:86+` (`OperationKind.localizedTitle` arm)
- Test: `Tests/CapsuleUnitTests/ContainerCLIUpdateModelTests.swift` (new)

**Interfaces:**
- Consumes: Task 4's `ContainerReleaseSource` / `MockContainerReleaseSource`, `TaskCenter.runStreaming`, `SemanticVersion` (CapsuleBackend).
- Produces (in `CapsuleDomain`):

```swift
@MainActor @Observable
public final class ContainerCLIUpdateModel {
    public static let updaterScriptPath = "/usr/local/bin/update-container.sh"
    public enum LatestState: Sendable, Equatable { case idle, checking, available(String), failed(String) }
    public private(set) var latest: LatestState
    public var updaterScriptAvailable: Bool { get }
    public var updateScriptPreview: String { get }
    public init(releaseSource:taskCenter:normalize:onActivity:containerPath:updaterScriptExists:openInstaller:runScriptInTerminal:)
    public func checkLatest() async
    public func installLatest()
    public func runUpdater()
    public static func updateScript(containerPath: String) -> String
    public static func isUpToDate(installed: String?, latest: String) -> Bool
}
```

plus `OperationKind.cliInstall` (title `"Download Installer"`, symbol `"arrow.down.app"`).

- [ ] **Step 1: Write failing tests** — `ContainerCLIUpdateModelTests.swift`:

```swift
//
//  ContainerCLIUpdateModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import Foundation
import XCTest

@testable import CapsuleDomain

@MainActor
final class ContainerCLIUpdateModelTests: XCTestCase {
    private var source: MockContainerReleaseSource!
    private var taskCenter: TaskCenter!
    private var openedInstallers: [URL] = []
    private var terminalScripts: [String] = []

    override func setUp() {
        super.setUp()
        source = MockContainerReleaseSource()
        taskCenter = TaskCenter()
        openedInstallers = []
        terminalScripts = []
    }

    private func makeModel(scriptExists: Bool = true) -> ContainerCLIUpdateModel {
        ContainerCLIUpdateModel(
            releaseSource: source,
            taskCenter: taskCenter,
            containerPath: "/usr/local/bin/container",
            updaterScriptExists: { scriptExists },
            openInstaller: { self.openedInstallers.append($0) },
            runScriptInTerminal: { self.terminalScripts.append($0) })
    }

    func testCheckLatestPublishesTag() async {
        let model = makeModel()
        await model.checkLatest()
        XCTAssertEqual(model.latest, .available("1.2.3"))
    }

    func testCheckLatestFailurePublishesMessage() async {
        source.failure = .network(message: "offline")
        let model = makeModel()
        await model.checkLatest()
        guard case let .failed(message) = model.latest else {
            return XCTFail("expected .failed, got \(model.latest)")
        }
        XCTAssertTrue(message.contains("offline"))
    }

    func testInstallLatestDownloadsAndOpensInstaller() async {
        let model = makeModel()
        model.installLatest()
        XCTAssertEqual(taskCenter.tasks.count, 1)
        let task = taskCenter.tasks[0]
        XCTAssertEqual(task.kind, .cliInstall)
        await task.wait()
        guard case .succeeded = task.state else {
            return XCTFail("expected success, got \(task.state): \(task.transcriptText)")
        }
        XCTAssertEqual(source.lastDownloadedAsset?.name, "container-installer-signed.pkg")
        XCTAssertEqual(openedInstallers.count, 1)
        XCTAssertEqual(
            openedInstallers.first?.lastPathComponent, "container-installer-signed.pkg")
        XCTAssertTrue(task.transcript.contains { $0.text == "100%" })
    }

    func testInstallLatestFailsWithoutSignedPackage() async {
        source = MockContainerReleaseSource(
            release: ContainerCLIRelease(
                tag: "9.9.9",
                assets: [
                    ContainerCLIReleaseAsset(
                        name: "container-installer-unsigned.pkg",
                        downloadURL: "https://example.com/unsigned.pkg")
                ]))
        let model = makeModel()
        model.installLatest()
        let task = taskCenter.tasks[0]
        await task.wait()
        guard case .failed = task.state else {
            return XCTFail("expected failure, got \(task.state)")
        }
        XCTAssertTrue(openedInstallers.isEmpty)
    }

    func testRunUpdaterHandsExactScriptToTerminal() {
        let model = makeModel(scriptExists: true)
        model.runUpdater()
        XCTAssertEqual(taskCenter.tasks.count, 0)
        XCTAssertEqual(
            terminalScripts,
            [
                "#!/bin/sh\n"
                    + "'/usr/local/bin/container' system stop\n"
                    + "sudo '/usr/local/bin/update-container.sh' "
                    + "&& '/usr/local/bin/container' system start\n"
            ])
    }

    func testRunUpdaterFallsBackToInstallWhenScriptMissing() async {
        let model = makeModel(scriptExists: false)
        model.runUpdater()
        XCTAssertTrue(terminalScripts.isEmpty)
        XCTAssertEqual(taskCenter.tasks.count, 1)
        XCTAssertEqual(taskCenter.tasks[0].kind, .cliInstall)
        await taskCenter.tasks[0].wait()
    }

    func testIsUpToDateComparesSemanticVersions() {
        XCTAssertTrue(ContainerCLIUpdateModel.isUpToDate(installed: "1.2.3", latest: "1.2.3"))
        XCTAssertTrue(ContainerCLIUpdateModel.isUpToDate(installed: "1.3.0", latest: "1.2.9"))
        XCTAssertFalse(ContainerCLIUpdateModel.isUpToDate(installed: "1.0.0", latest: "1.2.3"))
        XCTAssertFalse(ContainerCLIUpdateModel.isUpToDate(installed: nil, latest: "1.2.3"))
        XCTAssertFalse(ContainerCLIUpdateModel.isUpToDate(installed: "junk", latest: "1.2.3"))
    }

    func testOperationKindHasTitleAndSymbol() {
        XCTAssertEqual(OperationKind.cliInstall.title, "Download Installer")
        XCTAssertFalse(OperationKind.cliInstall.symbolName.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter ContainerCLIUpdateModelTests` → FAIL.
- [ ] **Step 3: Implement.** `TaskCenter.swift`: add `case cliInstall` to `OperationKind`, `case .cliInstall: return "Download Installer"` to `title`, `case .cliInstall: return "arrow.down.app"` to `symbolName`. `LocalizedDisplay.swift` `OperationKind.localizedTitle`: `case .cliInstall: return uiString("Download Installer")`. `ContainerCLIUpdateModel.swift` (license header, then):

```swift
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Installing and
//  updating the `container` CLI itself cannot go through the container port (there is no
//  binary to run), so this model speaks the release port for downloads and hands
//  privileged updates to an injected Terminal closure — mirroring `DNSModel`'s seam.

import CapsuleBackend
import Foundation
import Observation

@MainActor
@Observable
public final class ContainerCLIUpdateModel {
    /// Where Apple's pkg installs its own updater script.
    public static let updaterScriptPath = "/usr/local/bin/update-container.sh"

    /// The latest-release lookup the About pane binds to.
    public enum LatestState: Sendable, Equatable {
        case idle
        case checking
        case available(String)
        case failed(String)
    }

    public private(set) var latest: LatestState = .idle
    /// The pkg URL the most recent successful install task downloaded (openable in
    /// Installer). Internal so the task's onSuccess can read it; tests observe the closure.
    private(set) var downloadedInstallerURL: URL?

    private let releaseSource: any ContainerReleaseSource
    private let taskCenter: TaskCenter
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void
    private let containerPath: String
    private let updaterScriptExists: () -> Bool
    private let openInstaller: @MainActor (URL) -> Void
    private let runScriptInTerminal: @MainActor (String) -> Void

    public init(
        releaseSource: any ContainerReleaseSource,
        taskCenter: TaskCenter,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in },
        containerPath: String,
        updaterScriptExists: @escaping () -> Bool,
        openInstaller: @escaping @MainActor (URL) -> Void,
        runScriptInTerminal: @escaping @MainActor (String) -> Void
    ) {
        self.releaseSource = releaseSource
        self.taskCenter = taskCenter
        self.normalize = normalize
        self.onActivity = onActivity
        self.containerPath = containerPath
        self.updaterScriptExists = updaterScriptExists
        self.openInstaller = openInstaller
        self.runScriptInTerminal = runScriptInTerminal
    }

    /// Whether Apple's updater script is present (drives the Update sheet's copy).
    public var updaterScriptAvailable: Bool { updaterScriptExists() }

    /// The exact handoff script the Update sheet previews.
    public var updateScriptPreview: String {
        Self.updateScript(containerPath: containerPath)
    }

    /// Looks up the latest release tag for the About pane. Serialized: a lookup already
    /// in flight wins.
    public func checkLatest() async {
        if case .checking = latest { return }
        latest = .checking
        do {
            let release = try await releaseSource.latestRelease()
            latest = .available(release.tag)
        } catch {
            latest = .failed(normalize(error).detail.explanation)
        }
    }

    /// Downloads the latest signed installer package as a cancellable Activity task and
    /// opens it in Installer on success. The user completes installation there (native
    /// administrator prompt + package signature validation).
    public func installLatest() {
        let source = releaseSource
        let directory = FileManager.default.temporaryDirectory
        downloadedInstallerURL = nil
        taskCenter.runStreaming(
            kind: .cliInstall,
            title: "Download container installer",
            onSuccess: { [weak self] in
                guard let self, let url = self.downloadedInstallerURL else { return }
                self.openInstaller(url)
                self.onActivity("Opened \(url.lastPathComponent) — finish installing there.")
            }
        ) {
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let release = try await source.latestRelease()
                        guard let asset = release.signedInstallerAsset else {
                            throw ContainerReleaseError.noSignedPackage(tag: release.tag)
                        }
                        continuation.yield(
                            OutputLine(source: .stdout, text: "Latest release: \(release.tag)"))
                        let destination = directory.appendingPathComponent(asset.name)
                        for try await line in source.downloadPackage(asset, to: destination) {
                            continuation.yield(line)
                        }
                        await MainActor.run { [weak self] in
                            self?.downloadedInstallerURL = destination
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        onActivity("Downloading the latest signed container installer from GitHub.")
    }

    /// Updates an installed CLI: hands Apple's updater script to Terminal (stop services →
    /// sudo update → restart on success). Falls back to the installer download when the
    /// script is missing (the pkg installs over the existing version).
    public func runUpdater() {
        guard updaterScriptExists() else {
            onActivity("Updater script not found — downloading the installer instead.")
            installLatest()
            return
        }
        runScriptInTerminal(Self.updateScript(containerPath: containerPath))
        onActivity("Opened Terminal to update the container CLI (requires administrator).")
    }

    /// The `.command` script body for the Terminal handoff. `system stop` is best-effort
    /// (the updater re-checks via launchctl and refuses to run over a live service);
    /// `system start` runs only after a successful update.
    public static func updateScript(containerPath: String) -> String {
        let container = shellQuoted(containerPath)
        let updater = shellQuoted(updaterScriptPath)
        return "#!/bin/sh\n"
            + "\(container) system stop\n"
            + "sudo \(updater) && \(container) system start\n"
    }

    /// Whether `installed` is at or beyond `latest`; unparsable/nil versions are treated
    /// as outdated so the UI errs toward offering the update.
    public static func isUpToDate(installed: String?, latest: String) -> Bool {
        guard let installed,
            let installedVersion = SemanticVersion(parsing: installed),
            let latestVersion = SemanticVersion(parsing: latest)
        else { return false }
        return !(installedVersion < latestVersion)
    }

    /// Single-quotes a token for safe inclusion in a `/bin/sh` command line.
    private static func shellQuoted(_ token: String) -> String {
        "'" + token.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
```

- [ ] **Step 4: Verify** — `swift test --filter ContainerCLIUpdateModelTests` → PASS; `make test` green.
- [ ] **Step 5: Commit** — `feat(domain): ContainerCLIUpdateModel — install task, updater handoff, cliInstall kind`

---

### Task 7: Composition root wiring + `cliMissing` UI-test scenario

**Files:**
- Modify: `Sources/CapsuleApp/AppEnvironment.swift` (property, `live()`, `uiTest()`, `make(...)`, `makeActions(...)`)
- Modify: `Sources/CapsuleApp/CapsuleScene.swift` (`@State` + init mirror of `aboutModel`, pass to `RootView`)
- Modify: `Sources/CapsuleUI/RootView.swift` (accept + hold `cliUpdateModel`, pass to `SystemDetailView` — the SystemDetailView/About changes land in Task 8; this task only threads the model to RootView's stored properties so the app still compiles, and defers the SystemDetailView parameter to Task 8 if needed to keep the diff coherent — if threading without a consumer trips "unused" warnings, fold the RootView/SystemDetailView threading into Task 8 instead and keep this task to AppEnvironment+Scene)
- Test: `Tests/CapsuleUnitTests/AppEnvironmentActionsTests.swift`

**Interfaces:**
- Consumes: Tasks 4–6.
- Produces: `AppEnvironment.cliUpdateModel: ContainerCLIUpdateModel`; `make(...)` gains `releaseSource: any ContainerReleaseSource` and `updaterScriptExists: @escaping () -> Bool`; `makeActions(systemModel:shell:cliUpdateModel:)` handles `.installContainerCLI` and `.retry`-style re-probe stays as-is; `uiTest()` supports `CAPSULE_UITEST_SCENARIO=cliMissing`.

- [ ] **Step 1: Write failing tests** — in `AppEnvironmentActionsTests` (mirror its existing construction of actions via `AppEnvironment.makeActions` or `.live()`; adapt to how the file builds fixtures):

```swift
    func testInstallContainerCLIRecoveryRegistersInstallTask() async {
        let environment = AppEnvironment.live()
        environment.actions.recover(.installContainerCLI)
        // recover dispatches into a Task; give the MainActor queue a beat.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(
            environment.taskCenter.tasks.contains { $0.kind == .cliInstall },
            "recover(.installContainerCLI) should start the installer download task")
    }
```

(`AppEnvironment.live()` uses the real `GitHubReleaseClient`, but the task registers before any network resolves, so the assertion is deterministic; the task itself may then fail — irrelevant here. If the existing test file has a mock-based `make` fixture, prefer it and seed `MockContainerReleaseSource`.)

- [ ] **Step 2: Run to verify failure** — `swift test --filter AppEnvironmentActionsTests` → FAIL (`.installContainerCLI` unhandled / model missing).
- [ ] **Step 3: Implement.**
  - `AppEnvironment`: add stored property `public let cliUpdateModel: ContainerCLIUpdateModel` (+ memberwise init param, mirroring `aboutModel` everywhere).
  - `live(updater:)`: pass `releaseSource: GitHubReleaseClient()` and `updaterScriptExists: { FileManager.default.isExecutableFile(atPath: ContainerCLIUpdateModel.updaterScriptPath) }`.
  - `uiTest()`: extend the scenario switch —

```swift
        let backend: any ContainerBackend
        switch scenario {
        case "serviceDown":
            backend = MockBackend(systemRunState: .stopped)
        case "cliMissing":
            let mock = MockBackend()
            mock.failure = .executableNotFound("/usr/local/bin/container")
            backend = mock
        default:
            backend = MockBackend()
        }
```

    and pass `releaseSource: MockContainerReleaseSource()`, `updaterScriptExists: { true }`.
  - `make(...)`: add parameters `releaseSource: any ContainerReleaseSource` and `updaterScriptExists: @escaping () -> Bool`; after `runPrivilegedInTerminal` add:

```swift
        let openInstallerPackage: @MainActor (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        }
        let runScriptInTerminal: @MainActor (String) -> Void = { script in
            openScriptInTerminal(script, terminalApp: currentTerminalApp())
        }
        let cliUpdateModel = ContainerCLIUpdateModel(
            releaseSource: releaseSource,
            taskCenter: taskCenter,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            containerPath: containerExecutablePath,
            updaterScriptExists: updaterScriptExists,
            openInstaller: openInstallerPackage,
            runScriptInTerminal: runScriptInTerminal
        )
```

    then `makeActions(systemModel: systemModel, shell: shell, cliUpdateModel: cliUpdateModel)` and thread `cliUpdateModel` into the `AppEnvironment(...)` call.
  - `makeActions`: add the parameter and, in the `recover` switch (before the grantPermission arms):

```swift
                case .installContainerCLI:
                    Task { @MainActor in cliUpdateModel.installLatest() }
```

  - `CapsuleScene`: add `@State private var cliUpdateModel: ContainerCLIUpdateModel`, initialize from `environment.cliUpdateModel`, pass to `RootView` alongside `aboutModel` (RootView accepts it per this task / Task 8).
- [ ] **Step 4: Verify** — `swift test --filter AppEnvironmentActionsTests` → PASS; `make test` green (update any `AppEnvironment`/`makeActions` fixture call sites the compiler flags — e.g. `CompositionTests`).
- [ ] **Step 5: Commit** — `feat(app): wire release source, installer/terminal closures, cliMissing scenario`

---

### Task 8: UI — About "Container CLI" section + Update sheet + threading

**Files:**
- Create: `Sources/CapsuleUI/UpdateContainerSheet.swift`
- Modify: `Sources/CapsuleUI/AboutDiagnosticsView.swift` (new section + sheet + `cliUpdate` param)
- Modify: `Sources/CapsuleUI/SystemDetailView.swift` (param + pass-through)
- Modify: `Sources/CapsuleUI/RootView.swift` (param + pass-through, if not already threaded in Task 7)
- Test: build + existing suites (presentation logic already unit-tested in Tasks 3/6); accessibility identifiers for Task 9

**Interfaces:**
- Consumes: `ContainerCLIUpdateModel` (`latest`, `checkLatest()`, `runUpdater()`, `updaterScriptAvailable`, `updateScriptPreview`, `isUpToDate`), `AboutModel.components`.
- Produces: accessibility identifiers `about-update-container-button`, `update-container-sheet`, `update-container-confirm`, `update-container-cancel`.

- [ ] **Step 1: Implement `UpdateContainerSheet.swift`** (license header, then):

```swift
//  Confirmation sheet for updating the container CLI: explains the Terminal handoff
//  (stop services → sudo updater → restart), previews the exact script, and only then
//  hands off — or, when the updater script is missing, offers the installer download.

import CapsuleDomain
import SwiftUI

struct UpdateContainerSheet: View {
    let scriptPreview: String
    let updaterScriptAvailable: Bool
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Update container")
                .font(.title2.bold())
            if updaterScriptAvailable {
                Text(
                    "Capsule stops container services, then opens Terminal to run Apple's "
                        + "updater script. Terminal asks for your administrator password "
                        + "(sudo); services restart after a successful update."
                )
                .foregroundStyle(.secondary)
                GroupBox {
                    Text(scriptPreview)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(
                    "The updater script was not found at "
                        + "/usr/local/bin/update-container.sh. Capsule will download the "
                        + "latest signed installer package instead — finish the update in "
                        + "Installer."
                )
                .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("update-container-cancel")
                Button(updaterScriptAvailable ? "Open Terminal & Update" : "Download Installer") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("update-container-confirm")
            }
        }
        .padding(20)
        .frame(width: 480)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("update-container-sheet")
    }
}
```

- [ ] **Step 2: Extend `AboutDiagnosticsView`** — add `let cliUpdate: ContainerCLIUpdateModel` and `@State private var showUpdateSheet = false`; insert between the Components and Compatibility sections:

```swift
                    Section("Container CLI") {
                        LabeledContent("Latest release") { latestLabel }
                        HStack {
                            Button("Update container…") { showUpdateSheet = true }
                                .accessibilityIdentifier("about-update-container-button")
                            Spacer()
                        }
                    }
```

with, on the `Form` (next to the existing `.task`): `.task { await cliUpdate.checkLatest() }`, and the sheet on the outer `Group`:

```swift
        .sheet(isPresented: $showUpdateSheet) {
            UpdateContainerSheet(
                scriptPreview: cliUpdate.updateScriptPreview,
                updaterScriptAvailable: cliUpdate.updaterScriptAvailable,
                onConfirm: { cliUpdate.runUpdater() })
        }
```

and the helper properties:

```swift
    private var installedCLIVersion: String? {
        model.components.first { $0.appName == "container" }?.version
    }

    @ViewBuilder private var latestLabel: some View {
        switch cliUpdate.latest {
        case .idle, .checking:
            Text("Checking…").foregroundStyle(.secondary)
        case let .available(tag):
            HStack(spacing: 8) {
                Text(tag).monospaced()
                if ContainerCLIUpdateModel.isUpToDate(installed: installedCLIVersion, latest: tag)
                {
                    Text("Up to date").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Update available").font(.caption).foregroundStyle(.orange)
                }
            }
        case let .failed(message):
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }
```

(The installed version already renders in the Components section; the section intentionally shows only the latest tag + comparison. The Update button stays enabled regardless of comparison — the script itself no-ops on same-version.)

- [ ] **Step 3: Thread the model** — `SystemDetailView`: add `let cliUpdateModel: ContainerCLIUpdateModel` and pass `cliUpdate: cliUpdateModel` to `AboutDiagnosticsView`; `RootView`: add the stored property + init param + pass to `SystemDetailView` (mirroring `aboutModel` at `RootView.swift:34/64/91/121`); confirm `CapsuleScene` passes it (Task 7).
- [ ] **Step 4: Verify** — `swift build` clean; `make test` green; `make app` builds. Launch once via `CAPSULE_UITEST=1 CAPSULE_UITEST_SCENARIO=healthy` is not scriptable here — rely on Task 9's XCUITests for interaction.
- [ ] **Step 5: Commit** — `feat(ui): Update container button + sheet on System ▸ About; onboarding threading`

---

### Task 9: XCUITests

**Files:**
- Modify: `App/CapsuleUITests/CapsuleUITests.swift`

**Interfaces:**
- Consumes: `cliMissing` scenario (Task 7), accessibility identifiers (Tasks 3/8), existing helpers `launchApp(scenario:)`, `element(_:in:)`, `labeled(_:in:)`.

- [ ] **Step 1: Add the tests:**

```swift
    @MainActor
    func testCLIMissingShowsNotInstalledBannerWithInstall() {
        let app = launchApp(scenario: "cliMissing")
        let banner = element("system-health-banner", in: app)
        XCTAssertTrue(
            banner.waitForExistence(timeout: 15), "the system-health banner should be present")
        XCTAssertTrue(
            banner.label.localizedCaseInsensitiveContains("not installed"),
            "with the CLI missing the banner should say so; got: \(banner.label)")
        XCTAssertTrue(
            labeled("Install container…", in: app).waitForExistence(timeout: 10),
            "an Install container recovery control should be offered")
    }

    @MainActor
    func testSystemAboutOffersUpdateContainer() {
        let app = launchApp()
        let sidebarSystem = element("sidebar-system", in: app)
        XCTAssertTrue(sidebarSystem.waitForExistence(timeout: 15))
        sidebarSystem.click()
        let aboutTab = labeled("About", in: app)
        XCTAssertTrue(aboutTab.waitForExistence(timeout: 10), "System should show an About tab")
        aboutTab.click()
        let updateButton = element("about-update-container-button", in: app)
        XCTAssertTrue(
            updateButton.waitForExistence(timeout: 15),
            "About should offer an Update container button")
        updateButton.click()
        XCTAssertTrue(
            element("update-container-sheet", in: app).waitForExistence(timeout: 10),
            "clicking Update container should present the confirmation sheet")
        element("update-container-cancel", in: app).click()
        XCTAssertFalse(
            element("update-container-sheet", in: app)
                .waitForExistence(timeout: 2),
            "Cancel should dismiss the sheet without opening Terminal")
    }
```

- [ ] **Step 2: Run** — build the app and run the UI tests the way CI does (`make app` then `xcodebuild test` per the `app-ui-tests` job in `.github/workflows/` — copy the exact invocation from there). Expected: both tests PASS. If the onboarding sheet intercepts clicks in `testSystemAboutOffersUpdateContainer`, dismiss it first via its Continue/Get Started button (`labeled("Get Started"...)`/`labeled("Continue"...)`) before navigating.
- [ ] **Step 3: Commit** — `test(ui): golden XCUITests for CLI-missing recovery and Update container sheet`

---

### Task 10: Integration probe, docs, full verification

**Files:**
- Create: `Tests/CapsuleIntegrationTests/ReleaseSourceIntegrationTests.swift`
- Modify: `CLAUDE.md` (module map line), `README.md` (the CapsuleRegistryClient description, wherever the module list names it)
- Verify: everything

- [ ] **Step 1: Integration test** (network, opt-in like its siblings — self-skips unless `CAPSULE_INTEGRATION=1`):

```swift
//
//  ReleaseSourceIntegrationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Live probe of the apple/container GitHub releases API (network!). Opt-in via
//  CAPSULE_INTEGRATION=1, mirroring SystemSurfaceIntegrationTests. Read-only: it fetches
//  release metadata and asserts the signed-asset contract; it never downloads the pkg.

import CapsuleBackend
import CapsuleRegistryClient
import XCTest

final class ReleaseSourceIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CAPSULE_INTEGRATION"] == "1",
            "live integration probes are opt-in (CAPSULE_INTEGRATION=1)")
    }

    func testLatestReleaseCarriesSignedInstaller() async throws {
        let release = try await GitHubReleaseClient().latestRelease()
        XCTAssertFalse(release.tag.isEmpty, "the latest release must carry a tag")
        XCTAssertNotNil(
            release.signedInstallerAsset,
            "apple/container releases are expected to publish a signed installer; assets: "
                + release.assets.map(\.name).joined(separator: ", "))
        XCTAssertTrue(
            release.signedInstallerAsset?.downloadURL.hasPrefix("https://") ?? false)
    }
}
```

Check `Package.swift`: if the `CapsuleIntegrationTests` target does not yet depend on `CapsuleRegistryClient`, add it to that target's dependencies (a test-target dependency, not a module edge — the architecture guard does not forbid it).

- [ ] **Step 2: Docs** — `CLAUDE.md` module map: change `CapsuleRegistryClient (the URLSession Docker Hub search adapter)` to `CapsuleRegistryClient (the URLSession adapters: Docker Hub search + apple/container GitHub releases)`. Make the matching wording tweak wherever `README.md` describes the module.
- [ ] **Step 3: Full verification** — `make format && make check && make test` all green; `make app` builds; `CAPSULE_INTEGRATION=1 swift test --filter ReleaseSourceIntegrationTests` passes live.
- [ ] **Step 4: Commit** — `test(integration)+docs: live release probe; RegistryClient charter covers GitHub releases`
