//
//  KernelManagerModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest
@testable import CapsuleDomain

@MainActor
final class KernelManagerModelTests: XCTestCase {

    func testCommandPreviewForLocalFile() {
        let m = KernelManagerModel(backend: MockBackend(), taskCenter: TaskCenter())
        m.draft.mode = .localFile
        m.draft.binaryPath = "/k/vmlinux"
        m.draft.arch = .arm64
        XCTAssertEqual(
            m.commandPreview,
            "container system kernel set --arch arm64 --binary /k/vmlinux")
    }

    func testValidationRequiresPathForLocalFile() {
        let m = KernelManagerModel(backend: MockBackend(), taskCenter: TaskCenter())
        m.draft.mode = .localFile
        XCTAssertNotNil(m.validationMessage)  // empty path → message
        m.draft.binaryPath = "/k/vmlinux"
        XCTAssertNil(m.validationMessage)
    }

    func testRecommendedIsAlwaysValid() {
        let m = KernelManagerModel(backend: MockBackend(), taskCenter: TaskCenter())
        m.draft.mode = .recommended
        XCTAssertNil(m.validationMessage)
    }

    func testInstallRecordsConfigurationViaBackend() async {
        let backend = MockBackend()
        let center = TaskCenter()
        let m = KernelManagerModel(backend: backend, taskCenter: center)
        m.draft.mode = .recommended
        m.install()
        await center.activeTasks.first?.wait()
        XCTAssertEqual(backend.lastKernelConfiguration?.source, .recommended)
    }

    func testLoadCurrentReadsKernelSection() async {
        let m = KernelManagerModel(backend: MockBackend(), taskCenter: TaskCenter())
        await m.loadCurrent()
        XCTAssertNotNil(m.currentKernelSummary)  // from properties [kernel].binaryPath
    }
}
