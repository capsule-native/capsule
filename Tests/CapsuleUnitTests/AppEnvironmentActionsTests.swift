//
//  AppEnvironmentActionsTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import CapsuleDomain
import XCTest

@testable import CapsuleApp
@testable import CapsuleUI

@MainActor
final class AppEnvironmentActionsTests: XCTestCase {
    /// A mock-backed CLI update model for `makeActions` fixtures: no network, no Terminal.
    /// (`TaskCenter()` can't be a default argument — its `@MainActor` init is not callable
    /// from the nonisolated default-argument context.)
    private func makeCLIUpdateModel(taskCenter: TaskCenter) -> ContainerCLIUpdateModel {
        ContainerCLIUpdateModel(
            releaseSource: MockContainerReleaseSource(),
            taskCenter: taskCenter,
            containerPath: "container",
            updaterScriptExists: { true },
            openInstaller: { _ in },
            runScriptInTerminal: { _ in })
    }

    func testRetryInTerminalRoutesToEmbeddedTerminal() {
        let shell = ShellState()
        let systemModel = SystemStatusModel(backend: MockBackend())
        let actions = AppEnvironment.makeActions(
            systemModel: systemModel, shell: shell,
            cliUpdateModel: makeCLIUpdateModel(taskCenter: TaskCenter()))
        actions.recover(.retryInTerminal(command: ["container", "kill", "c1"]))
        XCTAssertEqual(shell.terminalSession?.request.argv, ["container", "kill", "c1"])
        XCTAssertEqual(shell.terminalSession?.request.kind, .retry)
    }

    func testGrantAdministratorAppendsNetworkingGuidance() {
        let shell = ShellState()
        let systemModel = SystemStatusModel(backend: MockBackend())
        let actions = AppEnvironment.makeActions(
            systemModel: systemModel, shell: shell,
            cliUpdateModel: makeCLIUpdateModel(taskCenter: TaskCenter()))

        actions.recover(.grantPermission(.administrator))

        XCTAssertEqual(shell.activityLog.count, 1)
        XCTAssertTrue(
            shell.activityLog[0].contains("Settings > Networking"),
            "the admin safety net points the user at the Networking pane that performs the handoff")
    }

    func testInstallContainerCLIRecoveryRegistersInstallTask() async {
        let shell = ShellState()
        let systemModel = SystemStatusModel(backend: MockBackend())
        let taskCenter = TaskCenter()
        let actions = AppEnvironment.makeActions(
            systemModel: systemModel, shell: shell,
            cliUpdateModel: makeCLIUpdateModel(taskCenter: taskCenter))

        actions.recover(.installContainerCLI)
        // recover dispatches into a Task; give the MainActor queue a beat.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(
            taskCenter.tasks.contains { $0.kind == .cliInstall },
            "recover(.installContainerCLI) should start the installer download task")
    }

    func testGrantFileAccessStaysInTheNotAvailableBranch() {
        let shell = ShellState()
        let systemModel = SystemStatusModel(backend: MockBackend())
        let actions = AppEnvironment.makeActions(
            systemModel: systemModel, shell: shell,
            cliUpdateModel: makeCLIUpdateModel(taskCenter: TaskCenter()))

        actions.recover(.grantPermission(.fileAccess))

        XCTAssertEqual(shell.activityLog.count, 1)
        XCTAssertTrue(shell.activityLog[0].contains("not available yet"))
        XCTAssertFalse(
            shell.activityLog[0].contains("Networking"),
            "only .administrator gets the Networking guidance; other grants stay no-op")
    }

    /// TDD (Item 4): The pure helper must emit `exec sudo`, the absolute executable path,
    /// and the shell-quoted DNS argv. This is the extraction target tested independently of IO.
    func testPrivilegedTerminalScriptContainsSudoExecAndQuotedArgv() {
        let script = privilegedTerminalScript(
            ["system", "dns", "create", "--localhost", "127.0.0.1", "capsule.test"],
            executablePath: "/usr/local/bin/container")

        XCTAssertTrue(script.hasPrefix("#!/bin/sh\n"), "script must start with a sh shebang")
        XCTAssertTrue(script.contains("exec sudo"), "privileged handoff must use exec sudo")
        XCTAssertTrue(
            script.contains("/usr/local/bin/container"),
            "the absolute executable path must appear unmodified in the script")
        XCTAssertTrue(
            script.contains("capsule.test"),
            "the dns argv token must appear in the script")
    }
}
