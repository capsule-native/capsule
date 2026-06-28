//
//  CapsuleColorsTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import SwiftUI
import XCTest

@testable import CapsuleUI

final class CapsuleColorsTests: XCTestCase {
    func testRunningAndStoppedHaveDistinctColors() {
        XCTAssertNotEqual(
            CapsuleColors.containerStateColor(.running),
            CapsuleColors.containerStateColor(.stopped))
    }

    func testRunningIsGreen() {
        XCTAssertEqual(CapsuleColors.containerStateColor(.running), .green)
    }
}
