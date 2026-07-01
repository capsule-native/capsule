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

    func testCancelledStateIsNotActive() {
        XCTAssertFalse(TaskState.cancelled.isActive)
        XCTAssertTrue(TaskState.running(progress: nil).isActive)
    }

    func testNewOperationKindsHaveTitlesAndSymbols() {
        for kind in [OperationKind.build, .run, .export, .systemStart, .copy] {
            XCTAssertFalse(kind.title.isEmpty)
            XCTAssertFalse(kind.symbolName.isEmpty)
        }
        XCTAssertEqual(OperationKind.build.title, "Build")
        XCTAssertEqual(OperationKind.run.title, "Run")
    }

    func testCancelStopsRunningTaskAndMarksCancelled() async {
        let center = TaskCenter()
        let gate = AsyncStream<OutputLine>.makeStream()
        let task = center.runStreaming(kind: .build, title: "build") {
            AsyncThrowingStream { continuation in
                let pump = Task {
                    for await line in gate.stream { continuation.yield(line) }
                    continuation.finish()
                }
                continuation.onTermination = { _ in pump.cancel() }
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
            AsyncThrowingStream { continuation in
                continuation.yield(OutputLine(source: .stdout, text: "Downloading 50%"))
                continuation.finish()
            }
        }
        await task.wait()
        XCTAssertTrue(task.transcriptText.contains("50%"))
        XCTAssertEqual(task.state, .succeeded)
    }

    func testRetryOfCancelledTaskReRunsToSuccess() async {
        let center = TaskCenter()
        let flip = Flip(true)
        let gate = AsyncStream<OutputLine>.makeStream()
        let task = center.runStreaming(kind: .build, title: "build") {
            AsyncThrowingStream { continuation in
                if flip.shouldFail {
                    let pump = Task {
                        for await line in gate.stream { continuation.yield(line) }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in pump.cancel() }
                } else {
                    continuation.yield(OutputLine(source: .stdout, text: "built"))
                    continuation.finish()
                }
            }
        }
        await Task.yield()
        center.cancel(task)
        await task.wait()
        XCTAssertEqual(task.state, .cancelled)

        flip.shouldFail = false
        center.retry(task)
        await task.wait()
        XCTAssertEqual(task.state, .succeeded)
        XCTAssertEqual(task.transcript.map(\.text), ["built"])
    }

    func testClearFinishedRemovesOnlyCompletedTasks() async {
        let center = TaskCenter()
        let done = center.runAsync(kind: .save, title: "Save") {}
        await done.wait()

        center.clearFinished()

        XCTAssertTrue(center.tasks.isEmpty)
    }

    func test_machineCreate_kind_titleAndSymbol() {
        XCTAssertEqual(OperationKind.machineCreate.title, "Create Machine")
        XCTAssertFalse(OperationKind.machineCreate.symbolName.isEmpty)
    }

    func testRunStreamingThreadsInvocationOntoTask() async {
        let center = TaskCenter()
        let invocation = CommandInvocation(["image", "pull", "alpine"])
        let task = center.runStreaming(kind: .pull, title: "Pull alpine", invocation: invocation) {
            AsyncThrowingStream { $0.finish() }
        }
        XCTAssertEqual(task.invocation, invocation)
        await task.wait()
    }

    func testRunAsyncDefaultsInvocationToNil() async {
        let center = TaskCenter()
        let task = center.runAsync(kind: .save, title: "Save") {}
        XCTAssertNil(task.invocation)
        await task.wait()
    }
}
