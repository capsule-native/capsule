//
//  ArgumentBuilderTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleCLIBackend

final class ArgumentBuilderTests: XCTestCase {
    func testBuildsArgvInOrder() {
        let argv =
            ArgumentBuilder("container", "ls")
            .option("--all", enabled: true)
            .flag("--format", "json")
            .arguments

        XCTAssertEqual(argv, ["container", "ls", "--all", "--format", "json"])
    }

    func testFlagOmittedWhenValueIsNil() {
        let argv = ArgumentBuilder("ls").flag("--format", nil).arguments
        XCTAssertEqual(argv, ["ls"])
    }

    func testOptionOmittedWhenDisabled() {
        let argv = ArgumentBuilder("ls").option("--all", enabled: false).arguments
        XCTAssertEqual(argv, ["ls"])
    }
}
