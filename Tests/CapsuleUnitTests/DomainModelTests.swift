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

    func testContainerStateNormalizesUnknownValues() {
        XCTAssertEqual(Container(summary: sample(state: "exited")).state, .stopped)
        XCTAssertEqual(Container(summary: sample(state: "weird")).state, .unknown)
    }

    func testImageMapsBackendSummary() {
        let summary = ImageSummary(id: "sha256:abc", reference: "nginx:latest", sizeBytes: 4096)
        let image = Image(summary: summary)

        XCTAssertEqual(image.id, "sha256:abc")
        XCTAssertEqual(image.reference, "nginx:latest")
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
