//
//  TerminalSessionUITests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import XCTest

@testable import CapsuleUI

@MainActor
final class TerminalSessionUITests: XCTestCase {
    private func request() -> TerminalRequest {
        TerminalRequest(
            containerID: "c1", title: "Shell · c1",
            argv: ["container", "exec", "-it", "c1", "sh"], kind: .execShell)
    }

    func testOpenTerminalActivatesTerminalTabAndShowsPane() {
        let shell = ShellState(activityPanePresented: false, activityTab: .logs)
        shell.openTerminal(request())
        XCTAssertNotNil(shell.terminalSession)
        XCTAssertEqual(shell.activityTab, .terminal)
        XCTAssertTrue(shell.activityPanePresented)
    }

    func testCloseTerminalClearsSessionAndRestoresLogsTab() {
        let shell = ShellState()
        shell.openTerminal(request())
        shell.closeTerminal()
        XCTAssertNil(shell.terminalSession)
        XCTAssertEqual(shell.activityTab, .logs)
    }

    func testRestartBumpsGenerationAndClearsExit() {
        let session = TerminalSessionState(request: request())
        session.exit = .exited(code: 0)
        let before = session.generation
        session.restart()
        XCTAssertEqual(session.generation, before + 1)
        XCTAssertNil(session.exit)
    }

    func testBaseCasesExcludeTerminal() {
        XCTAssertEqual(ActivityTab.baseCases, [.logs, .tasks, .progress])
        XCTAssertEqual(ActivityTab.terminal.title, "Terminal")
    }

    func testExitStatusBannerText() {
        XCTAssertEqual(TerminalExitStatus.exited(code: 0).bannerText, "Session ended.")
        XCTAssertEqual(
            TerminalExitStatus.exited(code: 3).bannerText, "Session ended (exit 3).")
    }
}
