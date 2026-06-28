//
//  CLICommandTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The typed command factory is the single place argv is assembled, so views and the
//  backend never hand-concatenate CLI strings. Subcommand names mirror the real
//  `container` v1.0.0 surface (verified against `--help`).

import XCTest

@testable import CapsuleCLIBackend

final class CLICommandTests: XCTestCase {
    func testListContainers() {
        XCTAssertEqual(CLICommand.listContainers(all: false), ["list", "--format", "json"])
        XCTAssertEqual(
            CLICommand.listContainers(all: true),
            ["list", "--all", "--format", "json"]
        )
    }

    func testContainerLifecycle() {
        XCTAssertEqual(CLICommand.inspectContainer(id: "abc"), ["inspect", "abc"])
        XCTAssertEqual(CLICommand.startContainer(id: "abc"), ["start", "abc"])
        XCTAssertEqual(CLICommand.stopContainer(id: "abc"), ["stop", "abc"])
        XCTAssertEqual(CLICommand.removeContainer(id: "abc", force: false), ["delete", "abc"])
        XCTAssertEqual(
            CLICommand.removeContainer(id: "abc", force: true),
            ["delete", "--force", "abc"]
        )
        XCTAssertEqual(CLICommand.followLogs(container: "abc"), ["logs", "--follow", "abc"])
    }

    func testImages() {
        XCTAssertEqual(CLICommand.listImages(), ["image", "list", "--format", "json"])
        XCTAssertEqual(
            CLICommand.inspectImage(reference: "alpine"),
            ["image", "inspect", "alpine"]
        )
        XCTAssertEqual(CLICommand.pullImage(reference: "alpine"), ["image", "pull", "alpine"])
        XCTAssertEqual(CLICommand.removeImage(reference: "alpine"), ["image", "delete", "alpine"])
    }

    func testOtherFamilies() {
        XCTAssertEqual(CLICommand.listVolumes(), ["volume", "list", "--format", "json"])
        XCTAssertEqual(CLICommand.listNetworks(), ["network", "list", "--format", "json"])
        XCTAssertEqual(CLICommand.listRegistries(), ["registry", "list", "--format", "json"])
        XCTAssertEqual(CLICommand.listMachines(), ["machine", "list", "--format", "json"])
        XCTAssertEqual(CLICommand.builderStatus(), ["builder", "status", "--format", "json"])
        XCTAssertEqual(CLICommand.version(), ["system", "version", "--format", "json"])
    }

    func testSystemLifecycle() {
        XCTAssertEqual(CLICommand.systemStatus(), ["system", "status"])
        XCTAssertEqual(CLICommand.startSystem(), ["system", "start"])
        XCTAssertEqual(CLICommand.stopSystem(), ["system", "stop"])
    }
}
