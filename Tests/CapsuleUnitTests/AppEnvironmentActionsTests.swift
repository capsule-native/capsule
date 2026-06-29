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
    func testRetryInTerminalRoutesToEmbeddedTerminal() {
        let shell = ShellState()
        let systemModel = SystemStatusModel(backend: MockBackend())
        let actions = AppEnvironment.makeActions(systemModel: systemModel, shell: shell)
        actions.recover(.retryInTerminal(command: ["container", "kill", "c1"]))
        XCTAssertEqual(shell.terminalSession?.request.argv, ["container", "kill", "c1"])
        XCTAssertEqual(shell.terminalSession?.request.kind, .retry)
    }

    func testGrantAdministratorAppendsNetworkingGuidance() {
        let shell = ShellState()
        let systemModel = SystemStatusModel(backend: MockBackend())
        let actions = AppEnvironment.makeActions(systemModel: systemModel, shell: shell)

        actions.recover(.grantPermission(.administrator))

        XCTAssertEqual(shell.activityLog.count, 1)
        XCTAssertTrue(
            shell.activityLog[0].contains("Settings > Networking"),
            "the admin safety net points the user at the Networking pane that performs the handoff")
    }

    func testGrantFileAccessStaysInTheNotAvailableBranch() {
        let shell = ShellState()
        let systemModel = SystemStatusModel(backend: MockBackend())
        let actions = AppEnvironment.makeActions(systemModel: systemModel, shell: shell)

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
