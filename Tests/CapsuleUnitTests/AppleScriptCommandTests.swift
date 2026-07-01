//
//  AppleScriptCommandTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Unit-covers the AppleScript command arg-parsing that only otherwise runs under a live
//  `osascript` invocation: the empty-direct-parameter rejection, the includeStopped default,
//  and that a command dispatches to the installed AutomationService.
//

import CapsuleAutomation
import CapsuleBackend
import XCTest

@testable import CapsuleApp

final class AppleScriptCommandTests: XCTestCase {
    override func tearDown() {
        AutomationRuntime.service = nil
        super.tearDown()
    }

    func testRequireDirectStringRejectsEmptyAndAcceptsValue() throws {
        let command = CapsuleRunContainerCommand()
        command.directParameter = ""
        XCTAssertThrowsError(try command.requireDirectString("image")) { error in
            XCTAssertTrue(error is ScriptCommandError, "unexpected error: \(error)")
        }
        command.directParameter = "nginx"
        XCTAssertEqual(try command.requireDirectString("image"), "nginx")
    }

    func testListContainersCommandDefaultsToIncludingStopped() async throws {
        AutomationRuntime.service = LiveAutomationService(backend: MockBackend())
        let command = CapsuleListContainersCommand()
        // No `including stopped` argument supplied → the command defaults to all containers.
        let result = try await command.run(service: try AutomationRuntime.requireService())
        XCTAssertEqual(result as? [String], ["web", "db", "cache"])
    }

    func testContainerLogsCommandDispatchesToService() async throws {
        AutomationRuntime.service = LiveAutomationService(backend: MockBackend())
        let command = CapsuleContainerLogsCommand()
        command.directParameter = "web"
        let result = try await command.run(service: try AutomationRuntime.requireService())
        XCTAssertEqual(result as? String, "starting\nready")
    }
}
