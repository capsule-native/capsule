//
//  ShellNavigationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleUI

@MainActor
final class ShellNavigationTests: XCTestCase {
    func testNewStateDefaults() {
        let shell = ShellState()
        XCTAssertEqual(shell.systemTab, .overview)
        XCTAssertFalse(shell.commandPalettePresented)
        XCTAssertNil(shell.pendingSheet)
    }

    func testOpenSystemDeepLinksSelectionAndTab() {
        let shell = ShellState()
        shell.openSystem(tab: .storage)
        XCTAssertEqual(shell.selection, .system)
        XCTAssertEqual(shell.systemTab, .storage)
    }

    func testToggleCommandPalette() {
        let shell = ShellState()
        shell.toggleCommandPalette()
        XCTAssertTrue(shell.commandPalettePresented)
        shell.toggleCommandPalette()
        XCTAssertFalse(shell.commandPalettePresented)
    }

    func testPresentSetsPendingSheet() {
        let shell = ShellState()
        shell.present(.build)
        XCTAssertEqual(shell.pendingSheet?.id, "build")
        shell.present(.export(containerID: "abc"))
        XCTAssertEqual(shell.pendingSheet?.id, "export-abc")
    }

    func testSystemTabIsExhaustive() {
        XCTAssertEqual(SystemTab.allCases.count, 4)
        XCTAssertEqual(SystemTab.serviceLogs.id, "serviceLogs")
    }
}
