//
//  DockerHubClientTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Exercises `DockerHubClient` end-to-end through the `HTTPDataFetching` seam: exact
//  request construction (URLs, method, headers, percent-encoding), defensive decoding of
//  real hub.docker.com v2 captures (unknown fields ignored, malformed rows dropped), and
//  the mapping of every transport failure into `RegistrySearchError` — with cancellation
//  deliberately surfacing as `CancellationError` instead.

import CapsuleBackend
import Foundation
import XCTest

@testable import CapsuleRegistryClient

final class DockerHubClientTests: XCTestCase {
    private var fetcher: StubHTTPDataFetcher!
    private var client: DockerHubClient!

    override func setUp() {
        super.setUp()
        fetcher = StubHTTPDataFetcher()
        client = DockerHubClient(fetcher: fetcher)
    }

    // MARK: - Request construction

    func testSearchBuildsExactURLMethodAndAcceptHeader() async throws {
        fetcher.seed(Fixture.data("hub-search-repositories-empty"))

        _ = try await client.searchRepositories(query: "nginx", page: 1)

        let request = try XCTUnwrap(fetcher.lastRequest, "the client must issue one request")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://hub.docker.com/v2/search/repositories/?query=nginx&page=1&page_size=25",
            "the search URL must match hub.docker.com's v2 endpoint exactly")
        XCTAssertEqual(request.httpMethod, "GET", "catalog search is a read-only GET")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Accept"), "application/json",
            "the client must ask the hub for JSON explicitly")
    }

    func testSearchPercentEncodesTheQuery() async throws {
        fetcher.seed(Fixture.data("hub-search-repositories-empty"))

        _ = try await client.searchRepositories(query: "hello world", page: 1)

        XCTAssertEqual(
            fetcher.lastRequest?.url?.absoluteString,
            "https://hub.docker.com/v2/search/repositories/?query=hello%20world&page=1&page_size=25",
            "a space in the query must be percent-encoded, not sent raw")
    }

    func testSearchPercentEncodesPlusSigns() async throws {
        fetcher.seed(Fixture.data("hub-search-repositories-empty"))

        _ = try await client.searchRepositories(query: "c++", page: 1)

        XCTAssertEqual(
            fetcher.lastRequest?.url?.absoluteString,
            "https://hub.docker.com/v2/search/repositories/?query=c%2B%2B&page=1&page_size=25",
            "a raw '+' would be form-decoded as a space by the hub, silently changing the query")
    }

    func testTagsBuildsExactURLWithPageSizeBeforePage() async throws {
        fetcher.seed(Fixture.data("hub-repository-tags"))

        _ = try await client.listTags(repository: "library/nginx", page: 1)

        XCTAssertEqual(
            fetcher.lastRequest?.url?.absoluteString,
            "https://hub.docker.com/v2/repositories/library/nginx/tags/?page_size=25&page=1",
            "the tags URL must keep hub.docker.com's query-item order (page_size first)")
    }

    func testTagsPassesNamespacedRepositoryPathThrough() async throws {
        fetcher.seed(Fixture.data("hub-repository-tags"))

        _ = try await client.listTags(repository: "nginx/nginx-ingress", page: 2)

        XCTAssertEqual(
            fetcher.lastRequest?.url?.absoluteString,
            "https://hub.docker.com/v2/repositories/nginx/nginx-ingress/tags/?page_size=25&page=2",
            "a namespaced repository path must embed verbatim in the tags path")
    }

    // MARK: - Decoding real captures

    func testDecodesRealSearchCapture() async throws {
        fetcher.seed(Fixture.data("hub-search-repositories"))

        let page = try await client.searchRepositories(query: "nginx", page: 1)

        XCTAssertEqual(page.items.count, 4, "the trimmed capture carries four repository rows")
        let first = try XCTUnwrap(page.items.first)
        XCTAssertEqual(first.name, "nginx", "the official image leads the real result page")
        XCTAssertTrue(first.isOfficial, "hub marks library/nginx with is_official true")
        XCTAssertEqual(first.starCount, 21318, "star_count must carry through untouched")
        XCTAssertEqual(
            first.pullCount, 13_114_222_271,
            "pull counts overflow Int32, so the client must decode them as Int64")
        XCTAssertEqual(
            first.shortDescription, "Official build of Nginx.",
            "short_description must carry through untouched")
        let second = try XCTUnwrap(page.items.dropFirst().first)
        XCTAssertEqual(
            second.name, "nginx/nginx-ingress",
            "namespaced repositories keep their owner prefix")
        XCTAssertFalse(second.isOfficial, "namespaced rows are not official images")
        XCTAssertTrue(page.hasNextPage, "a non-empty next URL means another page exists")
        XCTAssertEqual(page.totalCount, 288701, "count is the hub's total match count")
    }

    func testDecodesEmptySearchCapture() async throws {
        fetcher.seed(Fixture.data("hub-search-repositories-empty"))

        let page = try await client.searchRepositories(query: "zzz-no-hits", page: 1)

        XCTAssertTrue(page.items.isEmpty, "a zero-hit search yields no items")
        XCTAssertFalse(page.hasNextPage, "hub signals no further page with an empty next string")
        XCTAssertEqual(page.totalCount, 0, "the hub reports zero total matches")
    }

    func testDecodesRealTagsCaptureIgnoringNestedImagesAndUnknownFields() async throws {
        fetcher.seed(Fixture.data("hub-repository-tags"))

        let page = try await client.listTags(repository: "library/nginx", page: 1)

        XCTAssertEqual(
            page.items.map(\.name), ["trixie-perl", "stable-trixie-perl"],
            "both real rows must survive despite their nested images arrays and extra fields")
        let first = try XCTUnwrap(page.items.first)
        XCTAssertEqual(
            first.lastUpdated, "2026-06-25T22:52:42.349783Z",
            "last_updated must carry through raw, fractional seconds intact")
        XCTAssertEqual(first.sizeBytes, 75_271_303, "sizeBytes comes from full_size")
        XCTAssertEqual(
            first.digest,
            "sha256:e7500ce68ae1ebe3938fc06b3d3787bec86ca5338133b915fc48ab6fac78ac23",
            "the manifest digest must carry through untouched")
        XCTAssertTrue(page.hasNextPage, "a non-empty next URL means another page exists")
        XCTAssertEqual(page.totalCount, 1231, "count is the hub's total tag count")
    }

    // MARK: - Defensive decoding

    func testMalformedSearchRowIsDroppedWhileGoodRowsSurvive() async throws {
        fetcher.seed(
            json: """
                {"count": 3, "next": "", "previous": "", "results": [
                    {"repo_name": "alpha", "is_official": false},
                    {"repo_name": 42, "is_official": false},
                    {"repo_name": "omega", "is_official": true}
                ]}
                """)

        let page = try await client.searchRepositories(query: "x", page: 1)

        XCTAssertEqual(
            page.items.map(\.name), ["alpha", "omega"],
            "one malformed row must be dropped without blanking the whole page")
    }

    func testRowMissingRepoNameIsDropped() async throws {
        fetcher.seed(
            json: """
                {"count": 2, "next": "", "previous": "", "results": [
                    {"star_count": 7},
                    {"repo_name": "kept"}
                ]}
                """)

        let page = try await client.searchRepositories(query: "x", page: 1)

        XCTAssertEqual(
            page.items.map(\.name), ["kept"],
            "a row without a repository name is unusable and must be dropped")
    }

    func testMissingResultsKeyYieldsEmptyPageWithoutThrowing() async throws {
        fetcher.seed(json: #"{"count": 5, "next": null}"#)

        let page = try await client.searchRepositories(query: "x", page: 1)

        XCTAssertTrue(page.items.isEmpty, "a missing results key must decode as an empty page")
        XCTAssertFalse(page.hasNextPage, "a null next means no further page")
        XCTAssertEqual(page.totalCount, 5, "count still carries through when results is absent")
    }

    // MARK: - Error mapping

    func testHTTP429WithRetryAfterMapsToRateLimited() async {
        fetcher.seed(json: "{}", status: 429, headers: ["Retry-After": "42"])

        let error = await searchError()

        XCTAssertEqual(
            error, .rateLimited(retryAfterSeconds: 42),
            "a 429 with Retry-After must surface the cooldown seconds")
    }

    func testHTTP429WithoutRetryAfterMapsToRateLimitedNil() async {
        fetcher.seed(json: "{}", status: 429)

        let error = await searchError()

        XCTAssertEqual(
            error, .rateLimited(retryAfterSeconds: nil),
            "a 429 without Retry-After still stands apart from other statuses")
    }

    func testHTTP404SurfacesTheHubErrorMessage() async {
        fetcher.seed(json: #"{"message":"object not found","errinfo":{}}"#, status: 404)

        let error = await searchError()

        XCTAssertEqual(
            error, .httpStatus(code: 404, message: "object not found"),
            "hub error bodies carry a short message field the user should see")
    }

    func testHTTP500WithJunkBodyMapsToHTTPStatusWithoutMessage() async {
        fetcher.seed(json: "<html>oops</html>", status: 500)

        let error = await searchError()

        XCTAssertEqual(
            error, .httpStatus(code: 500, message: nil),
            "an undecodable error body must not invent a message")
    }

    func testCancelledURLErrorSurfacesAsCancellationError() async {
        fetcher.error = URLError(.cancelled)

        do {
            _ = try await client.searchRepositories(query: "nginx", page: 1)
            XCTFail("a cancelled transport must throw")
        } catch is CancellationError {
            // expected: a superseded search must never look like an outage
        } catch {
            XCTFail("URLError.cancelled must surface as CancellationError, got \(error)")
        }
    }

    func testNotConnectedURLErrorMapsToNetwork() async {
        fetcher.error = URLError(.notConnectedToInternet)

        let error = await searchError()

        guard case .network = error else {
            XCTFail(
                "an offline transport failure must map to .network, got \(String(describing: error))"
            )
            return
        }
    }

    func testGarbageBodyWithHTTP200MapsToDecodingFailed() async {
        fetcher.seed(json: "certainly not json")

        let error = await searchError()

        guard case .decodingFailed = error else {
            XCTFail(
                "an undecodable 200 body must map to .decodingFailed, got \(String(describing: error))"
            )
            return
        }
    }

    // MARK: - Helpers

    /// Runs a search expected to fail and returns the `RegistrySearchError` it threw.
    private func searchError(
        file: StaticString = #filePath, line: UInt = #line
    ) async -> RegistrySearchError? {
        do {
            _ = try await client.searchRepositories(query: "nginx", page: 1)
            XCTFail("the search was expected to throw", file: file, line: line)
            return nil
        } catch let error as RegistrySearchError {
            return error
        } catch {
            XCTFail(
                "expected RegistrySearchError, got \(error)", file: file, line: line)
            return nil
        }
    }
}
