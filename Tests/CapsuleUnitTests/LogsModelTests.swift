//
//  LogsModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class LogsModelTests: XCTestCase {
    func testSnapshotPopulatesLines() async {
        let backend = MockBackend(logLines: [
            OutputLine(source: .stdout, text: "hello"), OutputLine(source: .stdout, text: "world"),
        ])
        let model = LogsModel(backend: backend)
        model.follow = false
        model.start(id: "c1")
        await model.waitForLoad()
        XCTAssertEqual(model.lines.map(\.text), ["hello", "world"])
        XCTAssertEqual(model.containerID, "c1")
    }

    func testTailLimitsSnapshot() async {
        let backend = MockBackend(logLines: [
            OutputLine(source: .stdout, text: "a"), OutputLine(source: .stdout, text: "b"),
            OutputLine(source: .stdout, text: "c"),
        ])
        let model = LogsModel(backend: backend)
        model.follow = false
        model.tail = 2
        model.start(id: "c1")
        await model.waitForLoad()
        XCTAssertEqual(model.lines.map(\.text), ["b", "c"])
    }

    func testSearchFilters() async {
        let backend = MockBackend(logLines: [
            OutputLine(source: .stdout, text: "alpha"), OutputLine(source: .stdout, text: "beta"),
            OutputLine(source: .stdout, text: "alpha-2"),
        ])
        let model = LogsModel(backend: backend)
        model.follow = false
        model.start(id: "c1")
        await model.waitForLoad()
        model.searchText = "alpha"
        XCTAssertEqual(model.filteredLines.map(\.text), ["alpha", "alpha-2"])
    }

    func testTranscriptTextJoinsLines() async {
        let backend = MockBackend(logLines: [
            OutputLine(source: .stdout, text: "one"), OutputLine(source: .stdout, text: "two"),
        ])
        let model = LogsModel(backend: backend)
        model.follow = false
        model.start(id: "c1")
        await model.waitForLoad()
        XCTAssertEqual(model.transcriptText, "one\ntwo")
    }

    func testRestartWhileFollowingKeepsStreaming() async {
        // Regression: the replaced (cancelled) follow task must not clear `isStreaming` after
        // the successor has already set it true.
        let backend = MockBackend()
        backend.neverEndingLogStream = true
        let model = LogsModel(backend: backend)
        model.follow = true
        model.start(id: "a")
        await Task.yield()
        model.start(id: "b")  // cancels a's task, starts b's
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(model.isStreaming)
        XCTAssertEqual(model.containerID, "b")
        model.stop()
    }

    func testStopCancelsFollowStream() async {
        let backend = MockBackend()
        backend.neverEndingLogStream = true
        let model = LogsModel(backend: backend)
        model.follow = true
        model.start(id: "c1")
        await Task.yield()
        model.stop()
        await model.waitForLoad()
        XCTAssertFalse(model.isStreaming)
    }
}
