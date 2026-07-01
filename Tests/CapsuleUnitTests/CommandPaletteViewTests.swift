//
//  CommandPaletteViewTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleUI

@MainActor
final class CommandPaletteViewTests: XCTestCase {
    private func action(_ id: String, _ title: String) -> CommandAction {
        CommandAction(
            id: id, title: title, subtitle: nil, symbol: "", shortcut: nil,
            isEnabled: true, run: {})
    }

    func testRankedEmptyQueryReturnsAllInOrder() {
        let all = [action("1", "Run"), action("2", "Build")]
        XCTAssertEqual(CommandPaletteView.ranked(all, query: "").map(\.id), ["1", "2"])
    }

    func testRankedFiltersNonMatches() {
        let all = [
            action("1", "Run Selected Image"),
            action("2", "Pull Image"),
            action("3", "Build from Folder"),
        ]
        let result = CommandPaletteView.ranked(all, query: "image")
        XCTAssertEqual(Set(result.map(\.id)), ["1", "2"])
    }

    func testRankedFirstIsBestMatch() {
        let all = [action("1", "Reclaim Disk Space"), action("2", "Run")]
        XCTAssertEqual(CommandPaletteView.ranked(all, query: "run").first?.id, "2")
    }
}
