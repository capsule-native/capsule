//
//  TerminalPreferenceTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class TerminalPreferenceTests: XCTestCase {
    private let all: [TerminalPreference] = [
        .systemDefault, .terminalApp, .iTerm, .ghostty, .warp,
        .custom(appPath: "/Applications/Foo.app"),
    ]

    func testStorageRoundTrips() {
        for pref in all {
            XCTAssertEqual(
                TerminalPreference(storage: pref.storageValue), pref, "round-trip \(pref)")
        }
    }

    func testBundleIdentifiers() {
        XCTAssertEqual(TerminalPreference.terminalApp.bundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(TerminalPreference.iTerm.bundleIdentifier, "com.googlecode.iterm2")
        XCTAssertEqual(TerminalPreference.ghostty.bundleIdentifier, "com.mitchellh.ghostty")
        XCTAssertEqual(TerminalPreference.warp.bundleIdentifier, "dev.warp.Warp-Stable")
        XCTAssertNil(TerminalPreference.systemDefault.bundleIdentifier)
        XCTAssertNil(TerminalPreference.custom(appPath: "/x").bundleIdentifier)
    }

    func testCustomAppPath() {
        XCTAssertEqual(
            TerminalPreference.custom(appPath: "/Applications/Foo.app").customAppPath,
            "/Applications/Foo.app")
        XCTAssertNil(TerminalPreference.terminalApp.customAppPath)
    }

    func testInitFromGarbageIsNil() {
        XCTAssertNil(TerminalPreference(storage: "nonsense"))
        XCTAssertNil(TerminalPreference(storage: ""))
    }

    func testCustomStorageValueFormat() {
        XCTAssertEqual(
            TerminalPreference.custom(appPath: "/Applications/Foo.app").storageValue,
            "custom:/Applications/Foo.app")
    }
}
