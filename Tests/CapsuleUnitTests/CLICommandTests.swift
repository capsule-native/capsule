//
//  CLICommandTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The typed command factory is the single place argv is assembled, so views and the
//  backend never hand-concatenate CLI strings. Subcommand names mirror the real
//  `container` v1.0.0 surface (verified against `--help`).

import CapsuleBackend
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
        XCTAssertEqual(CLICommand.stopContainer(id: "abc", options: .default), ["stop", "abc"])
        XCTAssertEqual(
            CLICommand.stopContainer(id: "abc", options: StopOptions(timeout: 0, signal: nil)),
            ["stop", "--time", "0", "abc"])
        XCTAssertEqual(
            CLICommand.stopContainer(id: "abc", options: StopOptions(timeout: 3, signal: "TERM")),
            ["stop", "--time", "3", "--signal", "TERM", "abc"])
        XCTAssertEqual(CLICommand.removeContainer(id: "abc", force: false), ["delete", "abc"])
        XCTAssertEqual(
            CLICommand.removeContainer(id: "abc", force: true),
            ["delete", "--force", "abc"]
        )
        XCTAssertEqual(CLICommand.followLogs(container: "abc"), ["logs", "--follow", "abc"])
    }

    func testDestructiveCommands() {
        XCTAssertEqual(CLICommand.killContainer(id: "a", signal: nil), ["kill", "a"])
        XCTAssertEqual(
            CLICommand.killContainer(id: "a", signal: "TERM"), ["kill", "--signal", "TERM", "a"])
        XCTAssertEqual(CLICommand.pruneContainers(), ["prune"])
        XCTAssertEqual(
            CLICommand.exportContainer(id: "a", to: URL(fileURLWithPath: "/tmp/x.tar")),
            ["export", "--output", "/tmp/x.tar", "a"])
    }

    func testStats() {
        XCTAssertEqual(
            CLICommand.containerStats(ids: ["a", "b"]),
            ["stats", "--no-stream", "--format", "json", "a", "b"])
        XCTAssertEqual(
            CLICommand.containerStats(ids: []),
            ["stats", "--no-stream", "--format", "json"])
    }

    func testRunAndBuildDelegateToConfigurationArguments() {
        let run = RunConfiguration(image: "nginx", detach: true)
        XCTAssertEqual(CLICommand.run(run), run.arguments)
        let build = BuildConfiguration(contextDirectory: URL(fileURLWithPath: "/p"), tag: "t:1")
        XCTAssertEqual(CLICommand.build(build), build.arguments)
    }

    func testCopyUsesCanonicalSubcommandNotAlias() {
        XCTAssertEqual(
            CLICommand.copy(source: "/h/f.txt", destination: "c1:/app/f.txt"),
            ["copy", "/h/f.txt", "c1:/app/f.txt"])
    }

    func testFetchLogsArgv() {
        XCTAssertEqual(
            CLICommand.fetchLogs(container: "c1", tail: nil, boot: false), ["logs", "c1"])
        XCTAssertEqual(
            CLICommand.fetchLogs(container: "c1", tail: 100, boot: false),
            ["logs", "-n", "100", "c1"])
        XCTAssertEqual(
            CLICommand.fetchLogs(container: "c1", tail: nil, boot: true), ["logs", "--boot", "c1"])
    }

    func testListDirectoryArgvUsesExecLs() {
        XCTAssertEqual(
            CLICommand.listDirectory(id: "c1", path: "/etc"), ["exec", "c1", "ls", "-la", "/etc"])
    }

    func testImages() {
        XCTAssertEqual(CLICommand.listImages(), ["image", "list", "--format", "json"])
        XCTAssertEqual(
            CLICommand.inspectImage(reference: "alpine"),
            ["image", "inspect", "alpine"]
        )
        XCTAssertEqual(
            CLICommand.pullImage(reference: "alpine", platform: nil), ["image", "pull", "alpine"])
        XCTAssertEqual(CLICommand.removeImage(reference: "alpine"), ["image", "delete", "alpine"])
    }

    func testImageTransferAndMaintenanceCommands() {
        XCTAssertEqual(
            CLICommand.pullImage(reference: "alpine", platform: "linux/arm64"),
            ["image", "pull", "--platform", "linux/arm64", "alpine"])
        XCTAssertEqual(
            CLICommand.pushImage(reference: "ghcr.io/me/app:1", platform: nil),
            ["image", "push", "ghcr.io/me/app:1"])
        XCTAssertEqual(
            CLICommand.pushImage(reference: "ghcr.io/me/app:1", platform: "linux/amd64"),
            ["image", "push", "--platform", "linux/amd64", "ghcr.io/me/app:1"])
        XCTAssertEqual(
            CLICommand.saveImage(
                references: ["alpine:latest"], to: URL(fileURLWithPath: "/tmp/a.tar"),
                platform: nil),
            ["image", "save", "--output", "/tmp/a.tar", "alpine:latest"])
        XCTAssertEqual(
            CLICommand.saveImage(
                references: ["a", "b"], to: URL(fileURLWithPath: "/tmp/a.tar"),
                platform: "linux/amd64"),
            ["image", "save", "--output", "/tmp/a.tar", "--platform", "linux/amd64", "a", "b"])
        XCTAssertEqual(
            CLICommand.loadImage(from: URL(fileURLWithPath: "/tmp/a.tar")),
            ["image", "load", "--input", "/tmp/a.tar"])
        XCTAssertEqual(
            CLICommand.tagImage(source: "alpine:latest", target: "ghcr.io/me/alpine:1"),
            ["image", "tag", "alpine:latest", "ghcr.io/me/alpine:1"])
        XCTAssertEqual(CLICommand.pruneImages(all: false), ["image", "prune"])
        XCTAssertEqual(CLICommand.pruneImages(all: true), ["image", "prune", "--all"])
    }

    /// The login argv must carry `--password-stdin` and the username, but NEVER the
    /// password — the secret is delivered through the child's stdin, so it cannot leak
    /// via `ps`, the debug log line, an error's `command:`, or any task transcript.
    func testRegistryLoginNeverPutsSecretOnArgv() {
        let argv = CLICommand.registryLogin(server: "ghcr.io", username: "me")
        XCTAssertEqual(
            argv, ["registry", "login", "--username", "me", "--password-stdin", "ghcr.io"])
        XCTAssertFalse(
            argv.contains {
                $0.localizedCaseInsensitiveContains("password") && $0 != "--password-stdin"
            },
            "no literal password may appear in argv")

        XCTAssertEqual(
            CLICommand.registryLogin(server: "ghcr.io", username: nil),
            ["registry", "login", "--password-stdin", "ghcr.io"])
        XCTAssertEqual(
            CLICommand.registryLogout(server: "ghcr.io"), ["registry", "logout", "ghcr.io"])
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
