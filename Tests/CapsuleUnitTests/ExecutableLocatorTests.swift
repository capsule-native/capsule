//
//  ExecutableLocatorTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Resolution order is injected with a fake filesystem so non-standard installs can be
//  validated without touching the real disk.

import Foundation
import XCTest

@testable import CapsuleCLIBackend

final class ExecutableLocatorTests: XCTestCase {
    private func resolve(
        explicit: String? = nil,
        present: Set<String>,
        path: [String] = []
    ) -> String? {
        ExecutableLocator.resolve(
            explicitPath: explicit,
            candidates: ["/usr/local/bin/container", "/opt/homebrew/bin/container"],
            pathDirectories: path,
            fileExists: present.contains
        )?.path
    }

    func testExplicitPathWinsWhenItExists() {
        let url = resolve(explicit: "/custom/container", present: ["/custom/container"])
        XCTAssertEqual(url, "/custom/container")
    }

    func testExplicitPathIgnoredWhenMissingThenFallsBackToCandidate() {
        let url = resolve(explicit: "/custom/container", present: ["/opt/homebrew/bin/container"])
        XCTAssertEqual(url, "/opt/homebrew/bin/container")
    }

    func testProbesCandidatesInOrder() {
        let url = resolve(present: ["/opt/homebrew/bin/container"])
        XCTAssertEqual(url, "/opt/homebrew/bin/container")
    }

    func testFallsBackToPathDirectoriesWhenNoCandidateExists() {
        let url = resolve(present: ["/some/tool/dir/container"], path: ["/some/tool/dir"])
        XCTAssertEqual(url, "/some/tool/dir/container")
    }

    func testReturnsNilWhenNothingResolves() {
        XCTAssertNil(resolve(present: []))
    }
}
