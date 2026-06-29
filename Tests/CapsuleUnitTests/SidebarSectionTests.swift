//
//  SidebarSectionTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import XCTest

@testable import CapsuleUI

final class SidebarSectionTests: XCTestCase {
    func testHasAllSixSections() {
        XCTAssertEqual(SidebarSection.allCases.count, 6)
    }

    func testResourceSectionsDisabledWithoutFeatures() {
        XCTAssertFalse(SidebarSection.containers.isEnabled(features: []))
        XCTAssertFalse(SidebarSection.images.isEnabled(features: []))
    }

    func testResourceSectionEnabledWhenFeaturePresent() {
        XCTAssertTrue(SidebarSection.containers.isEnabled(features: [.containers]))
        XCTAssertTrue(SidebarSection.machines.isEnabled(features: [.machines]))
    }

    func testSystemSectionAlwaysEnabled() {
        XCTAssertTrue(SidebarSection.system.isEnabled(features: []))
    }

    func testEverySectionHasTitleAndSymbol() {
        for section in SidebarSection.allCases {
            XCTAssertFalse(section.title.isEmpty)
            XCTAssertFalse(section.symbolName.isEmpty)
        }
    }

    func testVolumesAndNetworksSectionsDisabledWithoutFeatures() {
        XCTAssertFalse(SidebarSection.volumes.isEnabled(features: []))
        XCTAssertFalse(SidebarSection.networks.isEnabled(features: []))
    }

    func testVolumesAndNetworksSectionsEnabledWithFeatures() {
        XCTAssertTrue(SidebarSection.volumes.isEnabled(features: [.volumes]))
        XCTAssertTrue(SidebarSection.networks.isEnabled(features: [.networks]))
    }

    func testVolumesAndNetworksRequiredFeatures() {
        XCTAssertEqual(SidebarSection.volumes.requiredFeature, .volumes)
        XCTAssertEqual(SidebarSection.networks.requiredFeature, .networks)
    }
}
