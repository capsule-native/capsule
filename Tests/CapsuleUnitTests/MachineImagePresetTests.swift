//
//  MachineImagePresetTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class MachineImagePresetTests: XCTestCase {
    func test_presets_nonEmpty_haveReferences() {
        XCTAssertFalse(MachineImagePreset.all.isEmpty)
        XCTAssertTrue(MachineImagePreset.all.allSatisfy { $0.reference.contains(":") })
        XCTAssertTrue(MachineImagePreset.all.contains { $0.reference.hasPrefix("alpine") })
    }
}
