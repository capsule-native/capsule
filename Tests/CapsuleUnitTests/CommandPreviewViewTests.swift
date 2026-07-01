//
//  CommandPreviewViewTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import SwiftUI
import XCTest

@testable import CapsuleUI

final class CommandPreviewViewTests: XCTestCase {
    func testInitWithAndWithoutEscalation() {
        let invocation = CommandInvocation(["run", "alpine"])
        _ = CommandPreviewView(invocation)
        var escalated: CommandInvocation?
        let view = CommandPreviewView(invocation, onEscalate: { escalated = $0 })
        XCTAssertNotNil(view)
        XCTAssertNil(escalated)
    }
}
