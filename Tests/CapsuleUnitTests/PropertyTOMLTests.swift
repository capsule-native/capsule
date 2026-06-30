//
//  PropertyTOMLTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest
@testable import CapsuleDomain

final class PropertyTOMLTests: XCTestCase {
    func testLintCleanConfigHasNoIssues() {
        let toml = "[build]\ncpus = 2\nrosetta = true\n\n[machine]\nmemory = \"16gb\"\n"
        XCTAssertTrue(PropertyTOML.lint(toml).isEmpty)
    }
    func testLintFlagsKeyOutsideSection() {
        XCTAssertEqual(PropertyTOML.lint("cpus = 2\n").first?.line, 1)
    }
    func testLintFlagsMissingEquals() {
        let issues = PropertyTOML.lint("[build]\ncpus 2\n")
        XCTAssertEqual(issues.first?.line, 2)
    }
    func testLintFlagsUnterminatedString() {
        let issues = PropertyTOML.lint("[build]\nname = \"oops\n")
        XCTAssertEqual(issues.first?.line, 2)
    }
    func testParseGroupsSections() {
        let parsed = PropertyTOML.parse("[build]\ncpus = 2\n[machine]\ncpus = 5\n")
        XCTAssertEqual(parsed["build"]?["cpus"], "2")
        XCTAssertEqual(parsed["machine"]?["cpus"], "5")
    }
    func testChangesReportsAddedRemovedChanged() {
        let old = "[build]\ncpus = 2\nmemory = \"2gb\"\n"
        let new = "[build]\ncpus = 4\n[machine]\ncpus = 5\n"
        let changes = PropertyTOML.changes(from: old, to: new)
        XCTAssertTrue(
            changes.contains { $0.contains("build.cpus") && $0.contains("2") && $0.contains("4") })
        XCTAssertTrue(changes.contains { $0.contains("build.memory") })  // removed
        XCTAssertTrue(changes.contains { $0.contains("machine.cpus") })  // added
    }
}
