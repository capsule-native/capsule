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
