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
}
