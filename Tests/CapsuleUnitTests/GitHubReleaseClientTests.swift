//
//  GitHubReleaseClientTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Exercises `GitHubReleaseClient` end-to-end through the `HTTPDataFetching` seam (mirroring
//  `DockerHubClientTests`): exact request construction, decoding of a release payload, and the
//  mapping of rate-limit / HTTP-failure / undecodable-body responses into `ContainerReleaseError`.

import CapsuleBackend
import Foundation
import XCTest

@testable import CapsuleRegistryClient

final class GitHubReleaseClientTests: XCTestCase {
    private var fetcher: StubHTTPDataFetcher!
    private var client: GitHubReleaseClient!

    override func setUp() {
        super.setUp()
        fetcher = StubHTTPDataFetcher()
        client = GitHubReleaseClient(fetcher: fetcher)
    }

    private static let releaseJSON = Data(
        """
        {
          "tag_name": "1.0.0",
          "assets": [
            {"name": "container-1.0.0-installer-signed.pkg",
             "browser_download_url": "https://github.com/apple/container/releases/download/1.0.0/container-1.0.0-installer-signed.pkg",
             "unexpected_field": 7},
            {"name": "container-installer-unsigned.pkg",
             "browser_download_url": "https://github.com/apple/container/releases/download/1.0.0/container-installer-unsigned.pkg"}
          ],
          "prerelease": false
        }
        """.utf8)

    func testLatestReleaseBuildsExactURLAndDecodes() async throws {
        fetcher.seed(Self.releaseJSON)

        let release = try await client.latestRelease()

        let request = try XCTUnwrap(fetcher.request(withURLContaining: "releases/latest"))
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.github.com/repos/apple/container/releases/latest")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(release.tag, "1.0.0")
        XCTAssertEqual(release.assets.count, 2)
        XCTAssertEqual(
            release.signedInstallerAsset?.name, "container-1.0.0-installer-signed.pkg")
    }

    func testRateLimitMapsToRateLimited() async {
        fetcher.seed(
            Data(), status: 429, headers: ["Retry-After": "30"])
        do {
            _ = try await client.latestRelease()
            XCTFail("expected a throw")
        } catch let error as ContainerReleaseError {
            XCTAssertEqual(error, .rateLimited(retryAfterSeconds: 30))
        } catch { XCTFail("unexpected error \(error)") }
    }

    func testHTTPFailureMapsToHTTPStatus() async {
        fetcher.seed(Data("{}".utf8), status: 500)
        do {
            _ = try await client.latestRelease()
            XCTFail("expected a throw")
        } catch let error as ContainerReleaseError {
            guard case .httpStatus(code: 500, message: _) = error else {
                return XCTFail("expected .httpStatus(500), got \(error)")
            }
        } catch { XCTFail("unexpected error \(error)") }
    }

    func testGarbageBodyMapsToDecodingFailed() async {
        fetcher.seed(Data("not json".utf8))
        do {
            _ = try await client.latestRelease()
            XCTFail("expected a throw")
        } catch let error as ContainerReleaseError {
            guard case .decodingFailed = error else {
                return XCTFail("expected .decodingFailed, got \(error)")
            }
        } catch { XCTFail("unexpected error \(error)") }
    }

    func testDownloadPackageRefusesNonHTTPSURL() async throws {
        let asset = ContainerCLIReleaseAsset(
            name: "container-installer-signed.pkg", downloadURL: "http://example.com/installer.pkg")
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)

        do {
            for try await _ in client.downloadPackage(asset, to: destination) {}
            XCTFail("expected a throw")
        } catch let error as ContainerReleaseError {
            guard case .network = error else {
                return XCTFail("expected .network, got \(error)")
            }
        } catch { XCTFail("unexpected error \(error)") }
    }
}
