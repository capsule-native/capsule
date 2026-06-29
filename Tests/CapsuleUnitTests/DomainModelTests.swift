//
//  DomainModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

final class DomainModelTests: XCTestCase {
    func testContainerMapsBackendSummary() {
        let summary = ContainerSummary(id: "abc123", name: "web", image: "nginx", state: "running")
        let container = Container(summary: summary)

        XCTAssertEqual(container.id, "abc123")
        XCTAssertEqual(container.name, "web")
        XCTAssertEqual(container.image, "nginx")
        XCTAssertEqual(container.state, .running)
    }

    func testContainerMapsIPAndCreationDate() {
        let summary = ContainerSummary(
            id: "abcdef0123456789", name: "web", image: "nginx", state: "running",
            ip: "10.0.0.2", createdAt: "2026-06-20T09:15:00Z")
        let container = Container(summary: summary)
        XCTAssertEqual(container.ip, "10.0.0.2")
        XCTAssertNotNil(container.createdAt)
        XCTAssertEqual(container.shortID, "abcdef012345")
    }

    func testContainerCarriesVolumeMountsAndNetworkNames() {
        let summary = ContainerSummary(
            id: "id", name: "web", image: "nginx", state: "running",
            volumeMounts: ["data", "cache"], networkNames: ["default"])
        let container = Container(summary: summary)
        XCTAssertEqual(container.volumeMounts, ["data", "cache"])
        XCTAssertEqual(container.networkNames, ["default"])
    }

    func testContainerAttachmentsDefaultEmptyWhenSummaryHasNone() {
        let summary = ContainerSummary(id: "id", name: "n", image: "i", state: "running")
        let container = Container(summary: summary)
        XCTAssertTrue(container.volumeMounts.isEmpty)
        XCTAssertTrue(container.networkNames.isEmpty)
    }

    func testContainerCreationDateInvalidStringBecomesNil() {
        let summary = ContainerSummary(
            id: "id", name: "n", image: "i", state: "running", createdAt: "not-a-date")
        XCTAssertNil(Container(summary: summary).createdAt)
    }

    func testContainerStateNormalizesUnknownValues() {
        XCTAssertEqual(Container(summary: sample(state: "exited")).state, .stopped)
        XCTAssertEqual(Container(summary: sample(state: "weird")).state, .unknown)
    }

    func testContainerStateMapsStopping() {
        XCTAssertEqual(Container(summary: sample(state: "stopping")).state, .stopping)
    }

    func testImageMapsBackendSummary() {
        let summary = ImageSummary(
            id: "sha256:abc", reference: "nginx:latest", sizeBytes: 4096, digest: "sha256:abc")
        let image = Image(summary: summary)

        // A tagged image is identified by its (unique) reference; the digest is retained.
        XCTAssertEqual(image.id, "nginx:latest")
        XCTAssertEqual(image.reference, "nginx:latest")
        XCTAssertEqual(image.repository, "nginx")
        XCTAssertEqual(image.tag, "latest")
        XCTAssertEqual(image.digest, "sha256:abc")
        XCTAssertEqual(image.sizeBytes, 4096)
    }

    func testResourceKindHasAllExpectedCases() {
        XCTAssertEqual(ResourceKind.allCases, [.container, .image, .volume, .network])
    }

    func testTaskStateActivity() {
        XCTAssertTrue(TaskState.running(progress: nil).isActive)
        XCTAssertFalse(TaskState.succeeded.isActive)
    }

    private func sample(state: String) -> ContainerSummary {
        ContainerSummary(id: "id", name: "n", image: "i", state: state)
    }
}
