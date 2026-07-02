//
//  ContainerCLIUpdateModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import Foundation
import XCTest

@testable import CapsuleDomain

@MainActor
final class ContainerCLIUpdateModelTests: XCTestCase {
    private var source: MockContainerReleaseSource!
    private var taskCenter: TaskCenter!
    private var openedInstallers: [URL] = []
    private var terminalScripts: [String] = []

    override func setUp() {
        super.setUp()
        source = MockContainerReleaseSource()
        taskCenter = TaskCenter()
        openedInstallers = []
        terminalScripts = []
    }

    private func makeModel(scriptExists: Bool = true) -> ContainerCLIUpdateModel {
        ContainerCLIUpdateModel(
            releaseSource: source,
            taskCenter: taskCenter,
            containerPath: "/usr/local/bin/container",
            updaterScriptExists: { scriptExists },
            openInstaller: { self.openedInstallers.append($0) },
            runScriptInTerminal: { self.terminalScripts.append($0) })
    }

    func testCheckLatestPublishesTag() async {
        let model = makeModel()
        await model.checkLatest()
        XCTAssertEqual(model.latest, .available("1.2.3"))
    }

    func testCheckLatestFailurePublishesMessage() async {
        source.failure = .network(message: "offline")
        let model = makeModel()
        await model.checkLatest()
        guard case let .failed(message) = model.latest else {
            return XCTFail("expected .failed, got \(model.latest)")
        }
        XCTAssertTrue(message.contains("offline"))
    }

    func testInstallLatestDownloadsAndOpensInstaller() async {
        let model = makeModel()
        model.installLatest()
        XCTAssertEqual(taskCenter.tasks.count, 1)
        let task = taskCenter.tasks[0]
        XCTAssertEqual(task.kind, .cliInstall)
        await task.wait()
        guard case .succeeded = task.state else {
            return XCTFail("expected success, got \(task.state): \(task.transcriptText)")
        }
        XCTAssertEqual(source.lastDownloadedAsset?.name, "container-installer-signed.pkg")
        XCTAssertEqual(openedInstallers.count, 1)
        XCTAssertEqual(
            openedInstallers.first?.lastPathComponent, "container-installer-signed.pkg")
        XCTAssertTrue(task.transcript.contains { $0.text == "100%" })
    }

    func testInstallLatestFailsWithoutSignedPackage() async {
        source = MockContainerReleaseSource(
            release: ContainerCLIRelease(
                tag: "9.9.9",
                assets: [
                    ContainerCLIReleaseAsset(
                        name: "container-installer-unsigned.pkg",
                        downloadURL: "https://example.com/unsigned.pkg")
                ]))
        let model = makeModel()
        model.installLatest()
        let task = taskCenter.tasks[0]
        await task.wait()
        guard case .failed = task.state else {
            return XCTFail("expected failure, got \(task.state)")
        }
        XCTAssertTrue(openedInstallers.isEmpty)
    }

    func testRunUpdaterHandsExactScriptToTerminal() {
        let model = makeModel(scriptExists: true)
        model.runUpdater()
        XCTAssertEqual(taskCenter.tasks.count, 0)
        XCTAssertEqual(
            terminalScripts,
            [
                "#!/bin/sh\n"
                    + "'/usr/local/bin/container' system stop\n"
                    + "sudo '/usr/local/bin/update-container.sh' "
                    + "&& '/usr/local/bin/container' system start\n"
            ])
    }

    func testRunUpdaterFallsBackToInstallWhenScriptMissing() async {
        let model = makeModel(scriptExists: false)
        model.runUpdater()
        XCTAssertTrue(terminalScripts.isEmpty)
        XCTAssertEqual(taskCenter.tasks.count, 1)
        XCTAssertEqual(taskCenter.tasks[0].kind, .cliInstall)
        await taskCenter.tasks[0].wait()
    }

    func testIsUpToDateComparesSemanticVersions() {
        XCTAssertTrue(ContainerCLIUpdateModel.isUpToDate(installed: "1.2.3", latest: "1.2.3"))
        XCTAssertTrue(ContainerCLIUpdateModel.isUpToDate(installed: "1.3.0", latest: "1.2.9"))
        XCTAssertFalse(ContainerCLIUpdateModel.isUpToDate(installed: "1.0.0", latest: "1.2.3"))
        XCTAssertFalse(ContainerCLIUpdateModel.isUpToDate(installed: nil, latest: "1.2.3"))
        XCTAssertFalse(ContainerCLIUpdateModel.isUpToDate(installed: "junk", latest: "1.2.3"))
    }

    func testOperationKindHasTitleAndSymbol() {
        XCTAssertEqual(OperationKind.cliInstall.title, "Download Installer")
        XCTAssertFalse(OperationKind.cliInstall.symbolName.isEmpty)
    }
}
