//
//  TerminalLauncherTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleApp
import CapsuleDomain
import Foundation
import XCTest

final class TerminalLauncherTests: XCTestCase {
    private let iTermURL = URL(fileURLWithPath: "/Applications/iTerm.app")

    func testSystemDefaultResolvesToNil() {
        XCTAssertNil(
            resolveTerminalApp(
                .systemDefault, lookup: { _ in self.iTermURL }, fileExists: { _ in true }))
    }

    func testInstalledBundleIDResolvesToItsURL() {
        let url = resolveTerminalApp(
            .iTerm,
            lookup: { $0 == "com.googlecode.iterm2" ? self.iTermURL : nil },
            fileExists: { _ in true })
        XCTAssertEqual(url, iTermURL)
    }

    func testNotInstalledBundleIDResolvesToNil() {
        XCTAssertNil(resolveTerminalApp(.ghostty, lookup: { _ in nil }, fileExists: { _ in true }))
    }

    func testCustomExistingPathResolvesToFileURL() {
        let url = resolveTerminalApp(
            .custom(appPath: "/Applications/Foo.app"),
            lookup: { _ in nil },
            fileExists: { $0 == "/Applications/Foo.app" })
        XCTAssertEqual(url, URL(fileURLWithPath: "/Applications/Foo.app"))
    }

    func testCustomMissingPathResolvesToNil() {
        XCTAssertNil(
            resolveTerminalApp(
                .custom(appPath: "/nope.app"), lookup: { _ in nil }, fileExists: { _ in false }))
    }
}
