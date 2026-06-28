//
//  RunConfigurationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  RunConfiguration.arguments is the single source of truth for the `container run` argv —
//  shared by the CLI adapter (detached) and the domain's interactive terminal request.

import CapsuleBackend
import XCTest

final class RunConfigurationTests: XCTestCase {
    func testDetachedRunArgv() {
        let config = RunConfiguration(
            image: "nginx:latest", name: "web", command: [], env: ["FOO=bar"],
            publishPorts: ["8080:80"], volumes: ["/h:/c"], workdir: "/app", user: nil,
            interactive: false, tty: false, detach: true, remove: true)
        XCTAssertEqual(
            config.arguments,
            [
                "run", "-d", "--rm", "--name", "web", "-e", "FOO=bar",
                "-p", "8080:80", "-v", "/h:/c", "-w", "/app", "nginx:latest",
            ])
    }

    func testInteractiveRunArgvWithCommand() {
        let config = RunConfiguration(
            image: "alpine", command: ["sh", "-c", "echo hi"], interactive: true, tty: true)
        XCTAssertEqual(config.arguments, ["run", "-i", "-t", "alpine", "sh", "-c", "echo hi"])
    }

    func testMinimalRunArgv() {
        XCTAssertEqual(RunConfiguration(image: "alpine").arguments, ["run", "alpine"])
    }

    func testMultipleEnvPortVolume() {
        let config = RunConfiguration(
            image: "img", env: ["A=1", "B=2"], publishPorts: ["80:80", "443:443"],
            volumes: ["/a:/a", "/b:/b"])
        XCTAssertEqual(
            config.arguments,
            [
                "run", "-e", "A=1", "-e", "B=2", "-p", "80:80", "-p", "443:443",
                "-v", "/a:/a", "-v", "/b:/b", "img",
            ])
    }
}
