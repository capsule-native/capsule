//
//  ImageTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The domain image model parses a backend reference into repository/tag, exposes the
//  full + short digest for unambiguous copy actions, and recognizes dangling images.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

final class ImageTests: XCTestCase {
    func testParsesStandardReferenceIntoRepositoryAndTag() {
        let image = Image(summary: summary(reference: "docker.io/library/alpine:latest"))
        XCTAssertEqual(image.repository, "docker.io/library/alpine")
        XCTAssertEqual(image.tag, "latest")
        XCTAssertFalse(image.isDangling)
    }

    func testParsesRegistryPortWithoutMistakingItForATag() {
        let image = Image(summary: summary(reference: "localhost:5000/myimage:1.0"))
        XCTAssertEqual(image.repository, "localhost:5000/myimage")
        XCTAssertEqual(image.tag, "1.0")
    }

    func testReferenceWithoutTagHasNilTag() {
        let image = Image(summary: summary(reference: "localhost:5000/myimage"))
        XCTAssertEqual(image.repository, "localhost:5000/myimage")
        XCTAssertNil(image.tag)
    }

    func testDigestPinnedReferenceHasNoTagAndIsNotDangling() {
        let image = Image(summary: summary(reference: "alpine@sha256:abc123"))
        XCTAssertEqual(image.repository, "alpine")
        XCTAssertNil(image.tag)
        XCTAssertFalse(image.isDangling)
    }

    func testDanglingReferenceIsRecognized() {
        let image = Image(summary: summary(reference: "<none>:<none>", digest: "sha256:deadbeef"))
        XCTAssertTrue(image.isDangling)
        XCTAssertNil(image.tag)
        XCTAssertEqual(image.id, "sha256:deadbeef", "a dangling row is identified by its digest")
    }

    func testNonDanglingIdIsTheReference() {
        let image = Image(summary: summary(reference: "alpine:latest"))
        XCTAssertEqual(image.id, "alpine:latest")
    }

    func testShortDigestTakesTwelveHexAfterTheAlgorithmPrefix() {
        let image = Image(
            summary: summary(
                reference: "alpine:latest",
                digest: "sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b"))
        XCTAssertEqual(image.shortDigest, "28bd5fe8b56d")
    }

    func testInitFromSummaryParsesCreationDate() {
        let image = Image(
            summary: summary(reference: "alpine:latest", createdAt: "2026-06-16T00:00:15Z"))
        XCTAssertNotNil(image.createdAt)
    }

    private func summary(
        reference: String, digest: String = "sha256:abc", createdAt: String? = nil
    ) -> ImageSummary {
        ImageSummary(
            id: digest, reference: reference, sizeBytes: 1234, digest: digest, createdAt: createdAt)
    }
}
