//
//  ContainerLifecycleModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import CapsuleDiagnostics
import XCTest

@testable import CapsuleDomain

/// A mutable container-state holder so `reloadList` can reflect the backend's mutations
/// back into the `currentState` seam during start verification.
@MainActor
final class LifecycleStateBox {
    var states: [String: ContainerState] = [:]
}

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
        backend.startFailure = .nonZeroExit(command: "start", code: 1, stderr: "boom")
        let m = model(backend: backend, state: { _ in .stopped })
        let result = await m.start(id: "e5f6a7b8", attach: false)
        XCTAssertEqual(result, .createdButNotStarted)
    }

    func testStartBackendUnavailableClassified() async {
        let backend = MockBackend()
        backend.startFailure = .executableNotFound("container")
        // Use the production normalizer: executableNotFound → daemonUnavailable.
        let m = ContainerLifecycleModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            currentState: { _ in .stopped }, settleAttempts: 1, settleDelay: .zero)
        let result = await m.start(id: "x", attach: false)
        XCTAssertEqual(result, .backendUnavailable)
    }

    func testStartAllSkipsRunningAndReportsTotalSelected() async {
        let backend = MockBackend()  // a1b2c3d4 running, e5f6a7b8 stopped, 0c1d2e3f running
        var activity: [String] = []
        let box = LifecycleStateBox()
        for c in (try? await backend.listContainers(all: true)) ?? [] {
            box.states[c.id] = ContainerState(backendState: c.state)
        }
        let m = ContainerLifecycleModel(
            backend: backend,
            onActivity: { activity.append($0) },
            reloadList: {
                for c in (try? await backend.listContainers(all: true)) ?? [] {
                    box.states[c.id] = ContainerState(backendState: c.state)
                }
            },
            currentState: { box.states[$0] ?? .unknown },
            settleAttempts: 2, settleDelay: .zero)

        await m.startAll(ids: ["a1b2c3d4", "e5f6a7b8", "0c1d2e3f"])

        // Only e5f6a7b8 was non-running; the message denominator is the total selected (3).
        XCTAssertTrue(activity.contains("Started 1 of 3 container(s)."), "got \(activity)")
    }

    func testStopHangsWhenBackendSlowAndDoesNotCancelStop() async {
        let backend = MockBackend()
        backend.stopDelay = .milliseconds(300)
        let m = ContainerLifecycleModel(
            backend: backend, currentState: { _ in .running },
            settleAttempts: 1, settleDelay: .zero, hangTimeout: .milliseconds(30))

        let outcome = await m.stop(id: "a1b2c3d4", options: .default)
        XCTAssertEqual(outcome, .hung)
        XCTAssertEqual(m.notice?.forceStopID, "a1b2c3d4")

        // The in-flight stop must NOT have been cancelled — it completes shortly after.
        var recorded = false
        for _ in 0..<50 where !recorded {
            if backend.lastStopOptions != nil {
                recorded = true
            } else {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        XCTAssertTrue(recorded, "the watchdog must let the stop continue in the background")
    }

    func testStopBenignPatternWithDaemonSignatureIsNotBenign() async {
        let backend = MockBackend()
        backend.failure = .nonZeroExit(
            command: "stop", code: 1, stderr: "connection refused: container is not running")
        let m = model(backend: backend, state: { _ in .running })
        let outcome = await m.stop(id: "a1b2c3d4", options: .default)
        guard case .failed = outcome else {
            return XCTFail(
                "daemon signature must override the benign 'not running' match: \(outcome)")
        }
    }

    func testAttachSingleFlightCancelsPriorStream() async {
        let backend = MockBackend(logLines: [OutputLine(source: .stdout, text: "x")])
        backend.neverEndingLogStream = true
        let m = model(backend: backend, state: { _ in .running })

        m.beginAttach(id: "a1b2c3d4")
        try? await Task.sleep(for: .milliseconds(40))
        m.beginAttach(id: "a1b2c3d4")  // single-flight: must cancel the first stream
        try? await Task.sleep(for: .milliseconds(40))

        XCTAssertGreaterThanOrEqual(
            backend.logStreamTerminations, 1, "the prior attach stream should be cancelled")
        m.detach()
    }

    func testKillReportsStopped() async {
        let backend = MockBackend()
        let m = model(backend: backend, state: { _ in .stopped })
        let outcome = await m.kill(id: "a1b2c3d4", signal: nil)
        XCTAssertEqual(outcome, .stopped)
        XCTAssertEqual(backend.lastKillSignal, nil)
    }

    func testDeleteUsesForceFlagAndRemoves() async {
        let backend = MockBackend()
        let m = model(backend: backend)
        await m.delete(id: "a1b2c3d4", force: true)
        let remaining = (try? await backend.listContainers(all: true))?.map(\.id) ?? []
        XCTAssertFalse(remaining.contains("a1b2c3d4"))
    }

    func testDeleteOfAlreadyGoneContainerIsBenign() async {
        let backend = MockBackend()
        backend.failure = .nonZeroExit(
            command: "delete", code: 1,
            stderr: "internalError: \"failed to delete container\" "
                + "(cause: \"notFound: container with ID a1b2c3d4 not found\")")
        var activity: [String] = []
        let m = ContainerLifecycleModel(
            backend: backend, onActivity: { activity.append($0) }, settleAttempts: 1,
            settleDelay: .zero)
        await m.delete(id: "a1b2c3d4", force: false)
        XCTAssertNil(m.notice, "a notFound delete is idempotent, not an error")
        XCTAssertTrue(activity.contains { $0.contains("already removed") }, "got \(activity)")
    }

    func testComputePruneTargetsAreStoppedOnly() async {
        let m = model(backend: MockBackend())
        let targets = await m.computePruneTargets()
        XCTAssertTrue(targets.allSatisfy { $0.state != .running })
        XCTAssertTrue(targets.contains { $0.id == "e5f6a7b8" })  // the seeded stopped one
    }

    func testPruneReportsReclaimedMessage() async {
        let m = model(backend: MockBackend())
        let summary = await m.prune()
        XCTAssertFalse(summary.message.isEmpty)
    }

    func testValidateExportFailsForRunning() {
        let m = model(state: { id in id == "run" ? .running : .stopped })
        XCTAssertFalse(m.validateExport(id: "run"))
        XCTAssertTrue(m.validateExport(id: "other"))
    }

    func testExportRecordsURL() async {
        let backend = MockBackend()
        let m = model(backend: backend)
        await m.export(id: "a1b2c3d4", to: URL(fileURLWithPath: "/tmp/c.tar"))
        XCTAssertEqual(backend.lastExportURL, URL(fileURLWithPath: "/tmp/c.tar"))
    }

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
            stderr: "internalError: \"failed to stop container\" "
                + "(cause: \"invalidState: container is not running\")")
        let m = model(backend: backend, state: { _ in .stopped })
        let outcome = await m.stop(id: "a1b2c3d4", options: .default)
        XCTAssertEqual(outcome, .alreadyStopped)  // not .failed, not daemonUnavailable
    }

    func testForceStopIssuesForcedOptions() async {
        let backend = MockBackend()
        let m = model(backend: backend, state: { _ in .stopped })
        _ = await m.forceStop(id: "a1b2c3d4")
        XCTAssertEqual(backend.lastStopOptions, .forced)
    }

    func testHangNoticeOffersForceAndKillCopy() {
        let m = model()
        let notice = m.makeHangNotice(id: "c1")
        XCTAssertEqual(notice.forceStopID, "c1")
        let killCopy = RecoveryAction.retryInTerminal(command: ["container", "kill", "c1"])
        XCTAssertTrue(notice.detail.recoveryActions.contains(killCopy))
    }

    func testAttachSingleFlightAndRingBufferThenDetach() async {
        let backend = MockBackend(
            logLines: (0..<300).map { OutputLine(source: .stdout, text: "\($0)") })
        let m = model(backend: backend, state: { _ in .running })
        _ = await m.start(id: "e5f6a7b8", attach: true)
        // Allow the attach pump to drain the seeded (synchronous) stream.
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(m.attachSession?.lines.count, 200)
        m.detach()
        XCTAssertNil(m.attachSession)
    }
}
