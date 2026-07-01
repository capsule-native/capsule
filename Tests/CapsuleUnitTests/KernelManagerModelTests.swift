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
        m.draft.arch = "arm64"
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

    // MARK: - remoteTar coverage

    func testCommandPreviewRemoteTarWithMember() {
        let m = KernelManagerModel(backend: MockBackend(), taskCenter: TaskCenter())
        m.draft.mode = .remoteTar
        m.draft.tarURL = "https://example.com/kernels.tar"
        m.draft.tarMember = "vmlinux"
        m.draft.arch = "arm64"
        let preview = m.commandPreview
        XCTAssertTrue(
            preview.contains("--tar https://example.com/kernels.tar"),
            "commandPreview should contain --tar <url>")
        XCTAssertTrue(
            preview.contains("--binary vmlinux"),
            "commandPreview should contain --binary <member> when tarMember is non-empty")
    }

    func testCommandPreviewRemoteTarWithoutMember() {
        let m = KernelManagerModel(backend: MockBackend(), taskCenter: TaskCenter())
        m.draft.mode = .remoteTar
        m.draft.tarURL = "https://example.com/kernels.tar"
        m.draft.tarMember = ""
        m.draft.arch = "arm64"
        let preview = m.commandPreview
        XCTAssertTrue(
            preview.contains("--tar https://example.com/kernels.tar"),
            "commandPreview should contain --tar <url>")
        XCTAssertFalse(
            preview.contains("--binary"),
            "commandPreview must NOT contain --binary when tarMember is empty")
    }

    func testValidationMessageForRemoteTarEmpty() {
        let m = KernelManagerModel(backend: MockBackend(), taskCenter: TaskCenter())
        m.draft.mode = .remoteTar
        XCTAssertNotNil(
            m.validationMessage,
            "validationMessage should be non-nil when tarURL is empty")
    }

    func testValidationMessageForRemoteTarFilled() {
        let m = KernelManagerModel(backend: MockBackend(), taskCenter: TaskCenter())
        m.draft.mode = .remoteTar
        m.draft.tarURL = "https://example.com/kernels.tar"
        XCTAssertNil(
            m.validationMessage,
            "validationMessage should be nil once tarURL is non-empty")
    }

    func testCommandInvocationDrivesPreview() {
        let m = KernelManagerModel(backend: MockBackend(), taskCenter: TaskCenter())
        m.draft.mode = .recommended
        XCTAssertEqual(m.commandInvocation.rawDisplay, m.commandPreview)
        XCTAssertTrue(m.commandPreview.hasPrefix("container "))
        XCTAssertTrue(m.commandPreview.contains("--recommended"))
    }
}
