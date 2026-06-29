//
//  MachineActionsModelCreateTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleBackend
@testable import CapsuleDomain

@MainActor
final class MachineActionsModelCreateTests: XCTestCase {
    private func make(_ mock: MockBackend) -> MachineActionsModel {
        MachineActionsModel(backend: mock, reloadList: {})
    }
    func test_commandPreview_reflectsDraft() {
        let a = make(MockBackend(machines: []))
        var d = MachineDraft(); d.image = "alpine:3.22"; d.name = "dev"; d.cpus = "4"
        XCTAssertEqual(
            a.commandPreview(for: d),
            "container machine create --name dev --cpus 4 --home-mount rw alpine:3.22")
    }
    func test_canCreate_requiresValidImage() {
        let a = make(MockBackend(machines: []))
        var d = MachineDraft()
        XCTAssertFalse(a.canCreate(d))
        d.image = "alpine:3.22"
        XCTAssertTrue(a.canCreate(d))
        d.cpus = "x"
        XCTAssertFalse(a.canCreate(d))
    }
    func test_create_succeeds_setsBanner() async {
        let mock = MockBackend(machines: [])
        let a = make(mock)
        var d = MachineDraft(); d.image = "alpine:3.22"; d.name = "dev"
        let ok = await a.create(draft: d)
        XCTAssertTrue(ok)
        XCTAssertEqual(mock.lastCreatedMachine?.image, "alpine:3.22")
        if case .created = a.banner?.kind {} else { XCTFail("expected created banner") }
    }
    func test_create_taskCenter_backgroundsAndSetsBannerOnSuccess() async {
        let mock = MockBackend(machines: [])
        let taskCenter = TaskCenter()
        let a = MachineActionsModel(backend: mock, reloadList: {}, taskCenter: taskCenter)
        var d = MachineDraft(); d.image = "alpine:3.22"; d.name = "dev"
        let ok = await a.create(draft: d)
        XCTAssertTrue(ok)  // returns true immediately; task is enqueued
        await taskCenter.tasks.last?.wait()
        XCTAssertNotNil(mock.lastCreatedMachine)
        if case .created = a.banner?.kind {} else { XCTFail("expected created banner") }
    }
}
