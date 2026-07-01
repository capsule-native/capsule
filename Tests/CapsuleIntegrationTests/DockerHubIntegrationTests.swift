//
//  DockerHubIntegrationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Live probes of hub.docker.com's public v2 API through the real `DockerHubClient`,
//  proving the wire assumptions (field names, pagination markers, fractional-second
//  timestamps, the `library` namespace) still hold. They need the network and stay
//  polite: three GETs total. Self-skip unless CAPSULE_INTEGRATION=1, mirroring
//  `CLIBackendIntegrationTests`.

import CapsuleBackend
import CapsuleDomain
import XCTest

@testable import CapsuleRegistryClient

final class DockerHubIntegrationTests: XCTestCase {
    private var integrationEnabled: Bool {
        ProcessInfo.processInfo.environment["CAPSULE_INTEGRATION"] == "1"
    }

    /// The single skip gate for every network-touching test.
    private func requireIntegration() throws {
        try XCTSkipUnless(
            integrationEnabled,
            "Set CAPSULE_INTEGRATION=1 to run integration tests (requires network access)."
        )
    }

    func testLiveSearchFindsOfficialNginx() async throws {
        try requireIntegration()
        let page = try await DockerHubClient().searchRepositories(query: "nginx", page: 1)

        XCTAssertFalse(page.items.isEmpty, "a live nginx search must return results")
        XCTAssertTrue(page.hasNextPage, "nginx has far more than one page of hits")
        let official = try XCTUnwrap(
            page.items.first(where: { $0.name == "nginx" }),
            "the official nginx repository should be on page one")
        XCTAssertTrue(official.isOfficial)
        XCTAssertNotNil(official.pullCount, "the official image carries a pull count")
    }

    func testLiveTagsForLibraryNginxParseIntoDomainDates() async throws {
        try requireIntegration()
        let page = try await DockerHubClient().listTags(repository: "library/nginx", page: 1)

        XCTAssertFalse(page.items.isEmpty, "library/nginx must have tags")
        XCTAssertTrue(page.hasNextPage, "nginx has hundreds of tags")
        let first = try XCTUnwrap(page.items.first)
        XCTAssertFalse(first.name.isEmpty)
        let tag = RegistryTag(summary: first)
        XCTAssertNotNil(
            tag.lastUpdated,
            "the live fractional-second timestamp must parse into a Date")
    }

    func testLiveUnknownRepositorySurfacesNotFound() async throws {
        try requireIntegration()
        do {
            _ = try await DockerHubClient().listTags(
                repository: "library/zz-capsule-definitely-not-real", page: 1)
            XCTFail("an unknown repository must not decode as a tag page")
        } catch let error as RegistrySearchError {
            guard case .httpStatus(let code, _) = error else {
                return XCTFail("expected httpStatus, got \(error)")
            }
            XCTAssertEqual(code, 404, "Hub answers 404 for unknown repositories")
        }
    }
}
