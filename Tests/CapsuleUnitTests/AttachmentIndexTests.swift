//
//  AttachmentIndexTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class AttachmentIndexTests: XCTestCase {
    // MARK: - ContainerAttachmentInfo

    func testContainerAttachmentInfoMapsFromDomainContainer() {
        let container = Container(
            id: "c1", name: "web", image: "nginx", state: .running,
            volumeMounts: ["data", "cache"], networkNames: ["default"])
        let info = ContainerAttachmentInfo(container: container)
        XCTAssertEqual(info.containerName, "web")
        XCTAssertEqual(info.volumeSources, ["data", "cache"])
        XCTAssertEqual(info.networkNames, ["default"])
    }

    func testContainerAttachmentInfoMemberwiseInit() {
        let info = ContainerAttachmentInfo(
            containerName: "db", volumeSources: ["pg"], networkNames: ["backend"])
        XCTAssertEqual(info.containerName, "db")
        XCTAssertEqual(info.volumeSources, ["pg"])
        XCTAssertEqual(info.networkNames, ["backend"])
    }

    // MARK: - AttachmentIndex.build

    func testBuildMapsVolumesAndNetworksToContainersInInputOrder() {
        let containers = [
            ContainerAttachmentInfo(
                containerName: "web", volumeSources: ["data"], networkNames: ["default"]),
            ContainerAttachmentInfo(
                containerName: "api", volumeSources: ["data", "logs"],
                networkNames: ["default", "backend"]),
        ]
        let index = AttachmentIndex.build(from: containers)
        XCTAssertEqual(index.containers(forVolume: "data"), ["web", "api"])
        XCTAssertEqual(index.containers(forVolume: "logs"), ["api"])
        XCTAssertEqual(index.containers(forNetwork: "default"), ["web", "api"])
        XCTAssertEqual(index.containers(forNetwork: "backend"), ["api"])
    }

    func testBuildWithNoAttachmentsYieldsEmptyMaps() {
        let index = AttachmentIndex.build(from: [
            ContainerAttachmentInfo(containerName: "web", volumeSources: [], networkNames: [])
        ])
        XCTAssertTrue(index.volumes.isEmpty)
        XCTAssertTrue(index.networks.isEmpty)
    }

    func testQueriesReturnEmptyArrayForUnknownNames() {
        let index = AttachmentIndex.build(from: [])
        XCTAssertEqual(index.containers(forVolume: "nope"), [])
        XCTAssertEqual(index.containers(forNetwork: "nope"), [])
    }
}
