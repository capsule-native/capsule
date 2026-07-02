//
//  RegistrySearchTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Tier-1 pure tests for the registry domain models: namespace normalization, pull
//  reference composition, and the summary-to-model mappings (including ISO-8601 parsing).

import CapsuleBackend
import Foundation
import XCTest

@testable import CapsuleDomain

final class RegistrySearchTests: XCTestCase {

    // MARK: - namespacedName

    func testNamespacedNameAddsLibraryNamespaceForOfficialStyleNames() {
        let repository = RegistryRepository(name: "nginx")
        XCTAssertEqual(
            repository.namespacedName, "library/nginx",
            "official images carry no namespace on the wire, so the implicit library namespace is added"
        )
    }

    func testNamespacedNameKeepsExplicitNamespaceUnchanged() {
        let repository = RegistryRepository(name: "nginx/nginx-ingress")
        XCTAssertEqual(
            repository.namespacedName, "nginx/nginx-ingress",
            "a name that already contains a namespace must pass through untouched")
    }

    // MARK: - pullReference(tag:)

    func testPullReferenceComposesOfficialImageReference() {
        let repository = RegistryRepository(name: "nginx", isOfficial: true)
        XCTAssertEqual(
            repository.pullReference(tag: "1.27"), "docker.io/library/nginx:1.27",
            "the pull reference should be fully qualified with registry, namespace, and tag")
    }

    func testPullReferenceComposesNamespacedImageReference() {
        let repository = RegistryRepository(name: "nginx/nginx-ingress")
        XCTAssertEqual(
            repository.pullReference(tag: "latest"), "docker.io/nginx/nginx-ingress:latest",
            "an explicit namespace should be used as-is in the pull reference")
    }

    // MARK: - RegistryRepository(summary:)

    func testRepositorySummaryMappingCarriesAllFields() {
        let summary = RegistryRepositorySummary(
            name: "nginx", shortDescription: "Official build of Nginx.", starCount: 21318,
            pullCount: 13_114_222_271, isOfficial: true,
            logoURL: "https://example.com/nginx-logo.png")
        let repository = RegistryRepository(summary: summary)
        XCTAssertEqual(repository.name, "nginx", "the wire name maps straight across")
        XCTAssertEqual(
            repository.shortDescription, "Official build of Nginx.",
            "the description maps straight across")
        XCTAssertEqual(repository.starCount, 21318, "the star count maps straight across")
        XCTAssertEqual(
            repository.pullCount, 13_114_222_271, "the pull count maps straight across")
        XCTAssertTrue(repository.isOfficial, "the official flag maps straight across")
        XCTAssertEqual(
            repository.logoURL, URL(string: "https://example.com/nginx-logo.png"),
            "the raw logo string parses into a URL")
    }

    func testRepositorySummaryMappingTolerantOfMissingOrUnparseableLogo() {
        XCTAssertNil(
            RegistryRepository(summary: RegistryRepositorySummary(name: "nginx")).logoURL,
            "no wire logo means default artwork, not a crash")
        let garbage = RegistryRepositorySummary(name: "nginx", logoURL: "ht tp://\u{7f}")
        XCTAssertNil(
            RegistryRepository(summary: garbage).logoURL,
            "an unparseable logo string degrades to default artwork")
    }

    // MARK: - RegistryTag(summary:)

    func testTagSummaryParsesFractionalSecondsTimestamp() throws {
        let tag = RegistryTag(
            summary: RegistryTagSummary(
                name: "latest", lastUpdated: "2026-06-25T22:52:42.349783Z",
                sizeBytes: 75_271_303))
        let date = try XCTUnwrap(
            tag.lastUpdated, "a fractional-seconds ISO-8601 timestamp should parse")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual(parts.year, 2026, "the parsed date should preserve the year")
        XCTAssertEqual(parts.month, 6, "the parsed date should preserve the month")
        XCTAssertEqual(parts.day, 25, "the parsed date should preserve the day")
        XCTAssertEqual(parts.hour, 22, "the parsed date should preserve the hour")
        XCTAssertEqual(parts.minute, 52, "the parsed date should preserve the minute")
        XCTAssertEqual(parts.second, 42, "the parsed date should preserve the second")
        XCTAssertEqual(tag.name, "latest", "the tag name maps straight across")
        XCTAssertEqual(tag.sizeBytes, 75_271_303, "the size maps straight across")
    }

    func testTagSummaryParsesPlainTimestampWithoutFraction() {
        let tag = RegistryTag(
            summary: RegistryTagSummary(name: "latest", lastUpdated: "2026-06-20T09:00:00Z"))
        XCTAssertNotNil(
            tag.lastUpdated, "an ISO-8601 timestamp without fractional seconds should parse")
    }

    func testTagSummaryToleratesGarbageTimestamp() {
        let tag = RegistryTag(
            summary: RegistryTagSummary(name: "latest", lastUpdated: "not a timestamp"))
        XCTAssertNil(tag.lastUpdated, "an unrecognizable timestamp should map to nil, not crash")
    }

    func testTagSummaryToleratesMissingTimestamp() {
        let tag = RegistryTag(summary: RegistryTagSummary(name: "latest", lastUpdated: nil))
        XCTAssertNil(tag.lastUpdated, "a missing timestamp should map to nil")
        XCTAssertNil(tag.sizeBytes, "a missing size should map to nil")
    }
}
