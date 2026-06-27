//
//  CapsuleUITests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  XCUITest target. These run through Xcode/xcodebuild against the built .app, not
//  through SwiftPM `swift test`. See `make app` / the CI notes in README.

import XCTest

final class CapsuleUITests: XCTestCase {
    @MainActor
    func testAppLaunchesToForeground() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "App did not reach the foreground after launch"
        )
    }
}
