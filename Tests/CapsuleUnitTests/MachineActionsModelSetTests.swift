//
//  MachineActionsModelSetTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleBackend
@testable import CapsuleDomain

@MainActor
final class MachineActionsModelSetTests: XCTestCase {
    func test_apply_recordsSettings_marksRestartRequired() async {
        let mock = MockBackend(machines: [MachineSummary(name: "dev", cpus: 2)])
        let a = MachineActionsModel(backend: mock, reloadList: {})
        var d = MachineSettingsDraft(); d.cpus = "8"; d.memory = "16G"
        let ok = await a.apply(settings: d, to: "dev")
        XCTAssertTrue(ok)
        XCTAssertEqual(mock.lastMachineSettings?.settings.cpus, 8)
        XCTAssertTrue(a.restartRequired("dev"))
    }
    func test_settingsProblem_invalidCpus() {
        let a = MachineActionsModel(backend: MockBackend(machines: []), reloadList: {})
        var d = MachineSettingsDraft(); d.cpus = "0"
        XCTAssertNotNil(a.settingsProblem(d))
    }

    func testSettingsInvocationDrivesPreview() {
        let m = MachineActionsModel(backend: MockBackend())
        var draft = MachineSettingsDraft()
        draft.cpus = "4"
        XCTAssertEqual(
            m.settingsPreview(name: "dev", draft: draft),
            m.settingsInvocation(name: "dev", draft: draft).displayString)
    }
}
