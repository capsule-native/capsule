//
//  RunModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class RunModelTests: XCTestCase {
    private func model(
        backend: any ContainerBackend = MockBackend(),
        terminalAvailable: @escaping @MainActor () -> Bool = { false },
        launchTerminal: @escaping @MainActor (TerminalRequest) -> Void = { _ in },
        copyCommand: @escaping @MainActor ([String]) -> Void = { _ in }
    ) -> RunModel {
        RunModel(
            backend: backend, taskCenter: TaskCenter(), terminalAvailable: terminalAvailable,
            launchTerminal: launchTerminal, copyCommand: copyCommand)
    }

    func testValidationRejectsEmptyImage() {
        let m = model()
        m.draft.image = "  "
        guard case let .failure(error) = m.validatedConfiguration(),
            case let .invalidInput(field, _) = error
        else { return XCTFail("expected an invalidInput on image") }
        XCTAssertEqual(field, "image")
    }

    func testCommandPreviewReflectsToggles() {
        let m = model()
        m.draft.image = "alpine"
        m.draft.interactive = true
        XCTAssertEqual(m.commandPreview, "container run -i -t alpine")
    }

    func testCommandPreviewFallsBackWhileEmpty() {
        XCTAssertEqual(model().commandPreview, "container run")
    }

    func testValidationTokenizesQuotedCommandAndDropsBlankRows() {
        let m = model()
        m.draft.image = "alpine"
        m.draft.command = "sh -c \"echo hi\""
        m.draft.envRows = ["FOO=bar", "   "]
        guard case let .success(config) = m.validatedConfiguration() else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(config.command, ["sh", "-c", "echo hi"])
        XCTAssertEqual(config.env, ["FOO=bar"])
    }

    func testRunDetachedRegistersRunTaskAndReloads() async {
        let center = TaskCenter()
        var reloaded = false
        let m = RunModel(
            backend: MockBackend(), taskCenter: center, reloadList: { reloaded = true })
        m.draft.image = "nginx"
        let task = m.runDetached()
        await task?.wait()
        XCTAssertEqual(center.tasks.first?.kind, .run)
        XCTAssertEqual(task?.state, .succeeded)
        XCTAssertTrue(reloaded)
    }

    func testRunInTerminalEmitsInteractiveRequest() {
        var launched: TerminalRequest?
        let m = model(terminalAvailable: { true }, launchTerminal: { launched = $0 })
        m.draft.image = "alpine"
        m.runInTerminal()
        XCTAssertEqual(launched?.argv, ["container", "run", "-i", "-t", "alpine"])
        XCTAssertEqual(launched?.kind, .runInteractive)
    }

    func testRunInTerminalCopiesWhenTerminalUnavailable() {
        var copied: [String]?
        let m = model(terminalAvailable: { false }, copyCommand: { copied = $0 })
        m.draft.image = "alpine"
        m.runInTerminal()
        XCTAssertEqual(copied, ["container", "run", "-i", "-t", "alpine"])
    }

    func testFailedDetachedRunRecordsTriageState() async {
        let backend = MockBackend()
        backend.failure = BackendError.nonZeroExit(
            command: "run", code: 125, stderr: "no such image")
        let m = RunModel(backend: backend, taskCenter: TaskCenter())
        m.draft.image = "ghost:latest"
        let task = m.runDetached()
        await task?.wait()
        // Allow the triage-recording task to observe the settled failure.
        for _ in 0..<5 where m.lastFailedConfig == nil { await Task.yield() }
        XCTAssertEqual(m.resolveImageReference, "ghost:latest")
        XCTAssertNotNil(m.lastFailedTask)
    }
}
