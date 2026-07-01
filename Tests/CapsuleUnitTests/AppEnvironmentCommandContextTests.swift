//
//  AppEnvironmentCommandContextTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleApp
import CapsuleUI
import XCTest

@MainActor
final class AppEnvironmentCommandContextTests: XCTestCase {
    func testLiveEnvironmentExposesCommandCatalog() {
        let env = AppEnvironment.live()
        let ids = CommandCatalog.actions(env.commandContext).map(\.id)
        XCTAssertTrue(ids.contains("toggle-inspector"))
        XCTAssertTrue(ids.contains("raw-command-preview"))
        XCTAssertTrue(ids.contains("open-system-logs"))
    }
}
