//
//  CapsuleAppDelegateTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import AppKit
import XCTest

@testable import CapsuleApp

final class CapsuleAppDelegateTests: XCTestCase {
    /// The whole point of the delegate: closing the last window must NOT quit Capsule, so it
    /// can stay resident behind its menu bar extra until the user explicitly quits.
    @MainActor
    func testDoesNotTerminateAfterLastWindowClosed() {
        let delegate = CapsuleAppDelegate()

        XCTAssertFalse(
            delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
