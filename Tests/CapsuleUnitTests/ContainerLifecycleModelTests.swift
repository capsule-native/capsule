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
