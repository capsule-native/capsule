//
//  DraftCodableTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class DraftCodableTests: XCTestCase {
    func testRunDraftRoundTrips() throws {
        var draft = RunDraft(image: "alpine:latest")
        draft.name = "web"
        draft.command = "sh -c 'echo hi'"
        draft.envRows = ["KEY=value"]
        draft.portRows = ["8080:80"]
        draft.volumeRows = ["/host:/container"]
        draft.interactive = true
        draft.remove = true
        draft.detach = true
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(RunDraft.self, from: data)
        XCTAssertEqual(decoded, draft)
    }

    func testBuildDraftEncodesContextDirectoryAsPlainPath() throws {
        var draft = BuildDraft()
        draft.contextDirectory = URL(fileURLWithPath: "/tmp/project")
        draft.tag = "app:dev"
        draft.dockerfile = "Dockerfile.web"
        draft.buildArgRows = ["KEY=value"]
        draft.noCache = true
        draft.preset = .plainProgress
        let data = try JSONEncoder().encode(draft)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        // A plain path string, NOT the synthesized URL keyed container.
        XCTAssertFalse(json.contains("\"relative\""))
        let decoded = try JSONDecoder().decode(BuildDraft.self, from: data)
        XCTAssertEqual(decoded, draft)
        XCTAssertEqual(decoded.contextDirectory?.path, "/tmp/project")
    }

    func testBuildDraftRoundTripsNilContext() throws {
        let draft = BuildDraft()
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(BuildDraft.self, from: data)
        XCTAssertNil(decoded.contextDirectory)
        XCTAssertEqual(decoded, draft)
    }
}
