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
}
