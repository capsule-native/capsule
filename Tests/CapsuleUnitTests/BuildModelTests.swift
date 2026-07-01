//
//  BuildModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class BuildModelTests: XCTestCase {
    private func model(backend: any ContainerBackend = MockBackend()) -> BuildModel {
        BuildModel(backend: backend, taskCenter: TaskCenter())
    }

    func testValidationRequiresContext() {
        let m = model()
        m.draft.tag = "t:1"
        guard case let .failure(error) = m.validatedConfiguration(),
            case let .invalidInput(field, _) = error
        else { return XCTFail("expected a context error") }
        XCTAssertEqual(field, "context")
    }

    func testValidationRequiresTag() {
        let m = model()
        m.draft.contextDirectory = URL(fileURLWithPath: "/p")
        guard case let .failure(error) = m.validatedConfiguration(),
            case let .invalidInput(field, _) = error
        else { return XCTFail("expected a tag error") }
        XCTAssertEqual(field, "tag")
    }

    func testPresetMapsToConfig() {
        let m = model()
        m.draft.contextDirectory = URL(fileURLWithPath: "/p")
        m.draft.tag = "t:1"
        m.draft.preset = .plainProgress
        guard case let .success(plain) = m.validatedConfiguration() else { return XCTFail() }
        XCTAssertTrue(plain.plainProgress)
        XCTAssertFalse(plain.noCache)

        m.draft.preset = .noCache
        guard case let .success(noCache) = m.validatedConfiguration() else { return XCTFail() }
        XCTAssertTrue(noCache.noCache)
        XCTAssertFalse(noCache.plainProgress)
    }

    func testBuildArgsAndDockerfileFlowIntoConfig() {
        let m = model()
        m.draft.contextDirectory = URL(fileURLWithPath: "/p")
        m.draft.tag = "t:1"
        m.draft.dockerfile = "Dockerfile.dev"
        m.draft.buildArgRows = ["A=1", "  "]
        guard case let .success(config) = m.validatedConfiguration() else { return XCTFail() }
        XCTAssertEqual(config.dockerfile, "Dockerfile.dev")
        XCTAssertEqual(config.buildArgs, ["A=1"])
    }

    func testBuildRegistersStreamingTaskAndReloads() async {
        let center = TaskCenter()
        var reloaded = false
        let m = BuildModel(
            backend: MockBackend(), taskCenter: center, reloadList: { reloaded = true })
        m.draft.contextDirectory = URL(fileURLWithPath: "/p")
        m.draft.tag = "t:1"
        let task = m.build()
        await task?.wait()
        XCTAssertEqual(center.tasks.first?.kind, .build)
        XCTAssertEqual(task?.state, .succeeded)
        XCTAssertTrue(reloaded)
    }

    func testRetryPlainForcesPlainProgress() async {
        let backend = MockBackend()
        let m = BuildModel(backend: backend, taskCenter: TaskCenter())
        m.draft.contextDirectory = URL(fileURLWithPath: "/p")
        m.draft.tag = "t:1"
        let task = m.retryPlain()
        await task?.wait()
        XCTAssertEqual(backend.lastBuildConfig?.plainProgress, true)
    }

    func testBuildCommandInvocationRedactsSecretBuildArg() {
        let m = BuildModel(backend: MockBackend(), taskCenter: TaskCenter())
        m.draft.contextDirectory = URL(fileURLWithPath: "/work/app")
        m.draft.tag = "app:dev"
        m.draft.buildArgRows = ["TOKEN=abc", "MODE=ci"]
        XCTAssertEqual(
            m.commandInvocation.rawDisplay,
            "container build --tag app:dev --build-arg TOKEN=abc --build-arg MODE=ci /work/app")
        XCTAssertEqual(
            m.commandInvocation.displayString,
            "container build --tag app:dev --build-arg TOKEN=‹redacted› --build-arg MODE=ci /work/app"
        )
    }

    func testBuildCommandInvocationFallsBackWhileEmpty() {
        XCTAssertEqual(
            BuildModel(backend: MockBackend(), taskCenter: TaskCenter()).commandInvocation
                .rawDisplay,
            "container build")
    }
}
