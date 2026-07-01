//
//  PrivacyDisclosureTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import XCTest

final class PrivacyDisclosureTests: XCTestCase {
    func testDefaultHasBothCollectedAndNeverCollectedItems() {
        let disclosure = PrivacyDisclosure.default
        XCTAssertFalse(disclosure.collected.isEmpty)
        XCTAssertFalse(disclosure.neverCollected.isEmpty)
    }

    func testItemIdentifiersAreUniqueWithinEachList() {
        let disclosure = PrivacyDisclosure.default
        XCTAssertEqual(
            disclosure.collected.map(\.id).count,
            Set(disclosure.collected.map(\.id)).count,
            "collected item ids must be unique so SwiftUI ForEach is stable")
        XCTAssertEqual(
            disclosure.neverCollected.map(\.id).count,
            Set(disclosure.neverCollected.map(\.id)).count,
            "never-collected item ids must be unique")
    }

    func testStatesLocalOnlyLoggingIsCollected() {
        let titles = PrivacyDisclosure.default.collected.map(\.title).joined(separator: "\n")
        XCTAssertTrue(
            titles.localizedCaseInsensitiveContains("local"),
            "the disclosure must state local diagnostic logging is collected")
    }

    func testStatesCrashSubmissionIsOptIn() {
        let details = PrivacyDisclosure.default.collected.map(\.detail).joined(separator: "\n")
        XCTAssertTrue(details.localizedCaseInsensitiveContains("opt in"))
        XCTAssertTrue(details.localizedCaseInsensitiveContains("disabled"))
    }

    func testNeverCollectsSecretsAndCommandContent() {
        let items = PrivacyDisclosure.default.neverCollected
        let text = items.map { "\($0.title) \($0.detail)" }.joined(separator: "\n")
        XCTAssertTrue(
            text.localizedCaseInsensitiveContains("secret")
                || text.localizedCaseInsensitiveContains("credential"),
            "must state secrets/credentials are never collected")
        XCTAssertTrue(
            text.localizedCaseInsensitiveContains("command content"),
            "must state command content is never collected unless approved")
    }

    func testDefaultIsEquatableAndStable() {
        XCTAssertEqual(PrivacyDisclosure.default, PrivacyDisclosure.default)
    }
}
