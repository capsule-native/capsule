//
//  TaskCenterTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The activity task center backing long image operations (pull/push/save/load): it
//  accumulates a transcript, records success/failure, and re-runs a failed task on retry.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

/// A mutable, Sendable flag so a test stream can change behaviour between the first run and
/// a retry.
private final class Flip: @unchecked Sendable {
    var shouldFail: Bool
    init(_ shouldFail: Bool) { self.shouldFail = shouldFail }
}

@MainActor
final class TaskCenterTests: XCTestCase {
    func testStreamingTaskAccumulatesTranscriptAndSucceeds() async {
        let center = TaskCenter()
        let task = center.runStreaming(kind: .pull, title: "Pull alpine") {
            AsyncThrowingStream { continuation in
                continuation.yield(OutputLine(source: .stdout, text: "Pulling"))
                continuation.yield(OutputLine(source: .stdout, text: "Done"))
                continuation.finish()
            }
        }

        await task.wait()

        XCTAssertEqual(task.state, .succeeded)
        XCTAssertEqual(task.transcript.map(\.text), ["Pulling", "Done"])
        XCTAssertEqual(center.tasks.count, 1)
        XCTAssertTrue(center.activeTasks.isEmpty)
    }

    func testStreamingTaskFailureRecordsFailedStateAndKeepsTranscript() async {
        let center = TaskCenter()
        let task = center.runStreaming(kind: .push, title: "Push app") {
            AsyncThrowingStream { continuation in
                continuation.yield(OutputLine(source: .stdout, text: "Uploading"))
                continuation.finish(
                    throwing: BackendError.nonZeroExit(
                        command: "container image push", code: 1, stderr: "unauthorized"))
            }
        }

        await task.wait()

        guard case .failed = task.state else {
            return XCTFail("expected .failed, got \(task.state)")
        }
        XCTAssertTrue(task.transcript.contains { $0.text == "Uploading" })
        XCTAssertTrue(
            task.transcript.contains { $0.text.contains("unauthorized") },
            "the failure transcript must keep the raw error visible")
    }

    func testRetryReRunsAFailedTaskToSuccess() async {
        let center = TaskCenter()
        let flip = Flip(true)
        let task = center.runStreaming(kind: .pull, title: "Pull alpine") {
            AsyncThrowingStream { continuation in
                if flip.shouldFail {
                    continuation.finish(
                        throwing: BackendError.nonZeroExit(
                            command: "container image pull", code: 1, stderr: "network error"))
                } else {
                    continuation.yield(OutputLine(source: .stdout, text: "Pulled"))
                    continuation.finish()
                }
            }
        }
        await task.wait()
        guard case .failed = task.state else { return XCTFail("expected first run to fail") }

        flip.shouldFail = false
        center.retry(task)
        await task.wait()

        XCTAssertEqual(task.state, .succeeded)
        XCTAssertEqual(task.transcript.map(\.text), ["Pulled"], "the transcript resets on retry")
    }

    func testNonStreamingTaskSucceeds() async {
        let center = TaskCenter()
        let task = center.runAsync(kind: .save, title: "Save alpine") {}
        await task.wait()
        XCTAssertEqual(task.state, .succeeded)
    }

    func testNonStreamingTaskFailureRecordsError() async {
        let center = TaskCenter()
        let task = center.runAsync(kind: .load, title: "Load archive") {
            throw BackendError.nonZeroExit(
                command: "container image load", code: 1, stderr: "invalid archive")
        }
        await task.wait()
        guard case .failed = task.state else { return XCTFail("expected .failed") }
        XCTAssertTrue(task.transcript.contains { $0.text.contains("invalid archive") })
    }

    func testClearFinishedRemovesOnlyCompletedTasks() async {
        let center = TaskCenter()
        let done = center.runAsync(kind: .save, title: "Save") {}
        await done.wait()

        center.clearFinished()

        XCTAssertTrue(center.tasks.isEmpty)
    }
}
