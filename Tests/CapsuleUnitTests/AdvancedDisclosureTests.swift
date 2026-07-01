//
//  AdvancedDisclosureTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import SwiftUI
import XCTest

@testable import CapsuleUI

final class AdvancedDisclosureTests: XCTestCase {
    func testInitWithDefaultTitleAndExternalBinding() {
        _ = AdvancedDisclosure { Text("body") }
        let expanded = Binding<Bool>(get: { true }, set: { _ in })
        let view = AdvancedDisclosure("Advanced Options", isExpanded: expanded) { Text("body") }
        XCTAssertNotNil(view)
    }
}
