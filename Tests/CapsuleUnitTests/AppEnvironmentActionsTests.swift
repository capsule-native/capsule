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
}
