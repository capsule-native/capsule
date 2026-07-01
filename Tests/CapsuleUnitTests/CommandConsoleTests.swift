//
//  CommandConsoleTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import CapsuleUI
import XCTest

final class CommandConsoleTests: XCTestCase {
    func testSeedTextUsesRedactedDisplayElseBarePrompt() {
        XCTAssertEqual(CommandConsoleView.seedText(for: nil), "container ")
        let seed = CommandInvocation(["run", "-it", "nginx"])
        XCTAssertEqual(CommandConsoleView.seedText(for: seed), seed.displayString)
    }

    func testResolvedArgvStripsLeadingContainerAndReprefixes() {
        XCTAssertEqual(
            CommandConsoleView.resolvedArgv(from: "container run -it nginx"),
            ["container", "run", "-it", "nginx"])
        XCTAssertEqual(
            CommandConsoleView.resolvedArgv(from: "run hello"),
            ["container", "run", "hello"])
        XCTAssertEqual(CommandConsoleView.resolvedArgv(from: "   "), ["container"])
    }
}
