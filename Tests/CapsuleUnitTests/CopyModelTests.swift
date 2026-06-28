//
//  CopyModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class CopyModelTests: XCTestCase {
    func testValidationRequiresEndpointsAndAbsoluteContainerPath() {
        let m = CopyModel(backend: MockBackend(), taskCenter: TaskCenter())
        XCTAssertNotNil(m.validationMessage)  // nothing set
        m.containerID = "c1"
        m.containerPath = "relative"
        m.hostURL = URL(fileURLWithPath: "/h/f")
        XCTAssertFalse(m.canCopy)
        XCTAssertTrue(m.validationMessage?.contains("absolute") ?? false)
        m.containerPath = "/app"
        XCTAssertTrue(m.canCopy)
        XCTAssertNil(m.validationMessage)
    }

    func testCopyToContainerRegistersTaskAndCallsBackend() async {
        let backend = MockBackend()
        let center = TaskCenter()
        let m = CopyModel(backend: backend, taskCenter: center)
        m.direction = .toContainer
        m.hostURL = URL(fileURLWithPath: "/h/f")
        m.containerID = "c1"
        m.containerPath = "/app/f"
        let task = m.copy()
        await task?.wait()
        XCTAssertEqual(center.tasks.first?.kind, .copy)
        XCTAssertEqual(backend.lastCopy?.direction, .toContainer)
        XCTAssertEqual(backend.lastCopy?.containerID, "c1")
        XCTAssertEqual(backend.lastCopy?.containerPath, "/app/f")
    }

    func testCopyFromContainerRoutesDirection() async {
        let backend = MockBackend()
        let m = CopyModel(backend: backend, taskCenter: TaskCenter())
        m.direction = .fromContainer
        m.hostURL = URL(fileURLWithPath: "/h/dest")
        m.containerID = "c2"
        m.containerPath = "/var/log"
        let task = m.copy()
        await task?.wait()
        XCTAssertEqual(backend.lastCopy?.direction, .fromContainer)
        XCTAssertEqual(backend.lastCopy?.containerID, "c2")
    }

    func testCopyReturnsNilWhenInvalid() {
        let m = CopyModel(backend: MockBackend(), taskCenter: TaskCenter())
        XCTAssertNil(m.copy())
    }

    func testBrowseReturnsEntriesAndDegradesWhenNoID() async {
        let m = CopyModel(backend: MockBackend(), taskCenter: TaskCenter())
        let emptyResult = await m.browse(path: "/")
        XCTAssertTrue(emptyResult.isEmpty)  // no container id yet
        m.containerID = "c1"
        let seededResult = await m.browse(path: "/")
        XCTAssertFalse(seededResult.isEmpty)  // seeded entries
    }
}
