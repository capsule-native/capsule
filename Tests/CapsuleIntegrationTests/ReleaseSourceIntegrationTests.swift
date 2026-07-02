//
//  ReleaseSourceIntegrationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Live probe of the apple/container GitHub releases API (network!). Opt-in via
//  CAPSULE_INTEGRATION=1, mirroring SystemSurfaceIntegrationTests. Read-only: it fetches
//  release metadata and asserts the signed-asset contract; it never downloads the pkg.

import CapsuleBackend
import CapsuleRegistryClient
import XCTest

final class ReleaseSourceIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CAPSULE_INTEGRATION"] == "1",
            "live integration probes are opt-in (CAPSULE_INTEGRATION=1)")
    }

    func testLatestReleaseCarriesSignedInstaller() async throws {
        let release = try await GitHubReleaseClient().latestRelease()
        XCTAssertFalse(release.tag.isEmpty, "the latest release must carry a tag")
        XCTAssertNotNil(
            release.signedInstallerAsset,
            "apple/container releases are expected to publish a signed installer; assets: "
                + release.assets.map(\.name).joined(separator: ", "))
        XCTAssertTrue(
            release.signedInstallerAsset?.downloadURL.hasPrefix("https://") ?? false)
    }
}
