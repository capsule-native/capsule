//
//  VolumeTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

final class VolumeTests: XCTestCase {
    func testInitFromSummaryMapsFieldsAndParsesDate() {
        let summary = VolumeSummary(
            name: "data",
            source: "/var/lib/containers/volumes/data",
            sizeBytes: 1024,
            options: ["journaling": "on"],
            labels: ["env": "dev"],
            createdAt: "2026-06-01T00:00:00Z")

        let volume = Volume(summary: summary, attachedContainers: ["web"])

        XCTAssertEqual(volume.id, "data")
        XCTAssertEqual(volume.name, "data")
        XCTAssertEqual(volume.source, "/var/lib/containers/volumes/data")
        XCTAssertEqual(volume.sizeBytes, 1024)
        XCTAssertEqual(volume.options, ["journaling": "on"])
        XCTAssertEqual(volume.labels, ["env": "dev"])
        XCTAssertNotNil(volume.createdAt)
        XCTAssertEqual(volume.attachedContainers, ["web"])
    }

    func testInitFromSummaryWithUnparseableDateYieldsNil() {
        let volume = Volume(summary: VolumeSummary(name: "x", createdAt: "not-a-date"))
        XCTAssertNil(volume.createdAt)
        XCTAssertTrue(volume.attachedContainers.isEmpty)
    }

    func testIdIsName() {
        XCTAssertEqual(Volume(name: "cache").id, "cache")
    }
}
