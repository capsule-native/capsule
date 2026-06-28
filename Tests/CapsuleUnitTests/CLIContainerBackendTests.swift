//
//  CLIContainerBackendTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Drives the CLI adapter through a stubbed runner: real `--format json` fixtures flow
//  in, decoded rows and typed errors flow out — with no process ever spawned.

import CapsuleBackend
import XCTest

@testable import CapsuleCLIBackend

final class CLIContainerBackendTests: XCTestCase {
    private func makeBackend(_ runner: StubProcessRunner) -> CLIContainerBackend {
        CLIContainerBackend(
            executableURL: URL(fileURLWithPath: "/usr/local/bin/container"),
            runner: runner
        )
    }

    // MARK: - Decoding real output

    func testListImagesDecodesRealJSONAndBuildsArgv() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: Fixture.text("images-ls"), stderr: "")

        let rows = try await makeBackend(stub).listImages()

        XCTAssertEqual(rows.first?.reference, "docker.io/library/alpine:latest")
        XCTAssertEqual(stub.lastCall, ["image", "list", "--format", "json"])
    }

    func testListContainersDecodesRowsWithIP() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: Fixture.text("containers-ls"), stderr: "")

        let rows = try await makeBackend(stub).listContainers(all: true)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.ip, "192.168.64.3")
        XCTAssertEqual(stub.lastCall, ["list", "--all", "--format", "json"])
    }

    func testVersionAndCapabilitiesProbeFromRealOutput() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: Fixture.text("system-version"), stderr: "")
        let backend = makeBackend(stub)

        let version = try await backend.version()
        XCTAssertEqual(version.client, "1.0.0")
        XCTAssertNotNil(version.server)

        let caps = try await backend.capabilities()
        XCTAssertTrue(caps.supports(.containers))
        XCTAssertTrue(caps.isSystemRunning)
    }

    func testSystemStatusParsesRunningAndBuildsArgv() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: "apiserver is running", stderr: "")

        let state = try await makeBackend(stub).systemStatus()

        XCTAssertEqual(state, .running)
        XCTAssertEqual(stub.lastCall, ["system", "status"])
    }

    func testSystemStatusReportsStoppedOnNonZeroExit() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 1, stdout: "apiserver is not running", stderr: "")

        let state = try await makeBackend(stub).systemStatus()

        XCTAssertEqual(state, .stopped)
    }

    func testStartSystemBuildsArgv() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: "", stderr: "")

        try await makeBackend(stub).startSystem()

        XCTAssertEqual(stub.lastCall, ["system", "start"])
    }

    func testStopSystemBuildsArgv() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: "", stderr: "")

        try await makeBackend(stub).stopSystem()

        XCTAssertEqual(stub.lastCall, ["system", "stop"])
    }

    func testStartSystemThrowsOnNonZeroExit() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 1, stdout: "", stderr: "boom")

        do {
            try await makeBackend(stub).startSystem()
            XCTFail("expected startSystem to throw on non-zero exit")
        } catch let BackendError.nonZeroExit(_, code, stderr) {
            XCTAssertEqual(code, 1)
            XCTAssertEqual(stderr, "boom")
        }
    }

    func testListNetworksDecodesRealFixture() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: Fixture.text("network-ls"), stderr: "")

        let networks = try await makeBackend(stub).listNetworks()

        XCTAssertEqual(networks.first?.id, "default")
        XCTAssertEqual(networks.first?.gateway, "192.168.64.1")
        XCTAssertEqual(networks.first?.subnet, "192.168.64.0/24")
    }

    // MARK: - Error mapping

    func testNonZeroExitThrowsTypedErrorWithCommandCodeAndStderr() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 1, stdout: "", stderr: "Error: not found")

        do {
            _ = try await makeBackend(stub).listContainers()
            XCTFail("expected a thrown error")
        } catch let BackendError.nonZeroExit(command, code, stderr) {
            XCTAssertTrue(command.contains("list"), "command was \(command)")
            XCTAssertEqual(code, 1)
            XCTAssertEqual(stderr, "Error: not found")
        }
    }

    // MARK: - Raw escape hatch

    func testRunRawReturnsRawOutputIncludingNonZeroExitWithoutThrowing() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 2, stdout: "stdout-text", stderr: "stderr-text")

        let raw = try await makeBackend(stub).runRaw(["some", "subcommand"])

        XCTAssertEqual(raw.exitCode, 2)
        XCTAssertEqual(raw.stdout, "stdout-text")
        XCTAssertEqual(raw.stderr, "stderr-text")
        XCTAssertEqual(stub.lastCall, ["some", "subcommand"])
    }

    // MARK: - Raw retention on inspect

    func testInspectContainerDecodesValueAndRetainsRaw() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: Fixture.text("containers-ls"), stderr: "")

        let parsed = try await makeBackend(stub).inspectContainer(id: "a1b2")

        XCTAssertEqual(parsed.value?.state, "running")
        XCTAssertFalse(parsed.raw.isEmpty)
        XCTAssertEqual(stub.lastCall, ["inspect", "a1b2"])
    }

    func testInspectDegradesToRawWhenSchemaNoLongerMatches() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: #"{"unexpected":"shape"}"#, stderr: "")

        let parsed = try await makeBackend(stub).inspectContainer(id: "x")

        XCTAssertNil(parsed.value, "decoding should fail gracefully")
        XCTAssertEqual(parsed.raw, #"{"unexpected":"shape"}"#, "raw payload must survive")
    }

    // MARK: - Lifecycle argv

    func testLifecycleCommandsIssueCorrectArgv() async throws {
        let stub = StubProcessRunner()
        let backend = makeBackend(stub)

        try await backend.startContainer(id: "c1")
        XCTAssertEqual(stub.lastCall, ["start", "c1"])

        try await backend.stopContainer(id: "c1", options: StopOptions(timeout: 2, signal: "TERM"))
        XCTAssertEqual(stub.lastCall, ["stop", "--time", "2", "--signal", "TERM", "c1"])

        try await backend.removeContainer(id: "c1", force: true)
        XCTAssertEqual(stub.lastCall, ["delete", "--force", "c1"])
    }

    func testKillAndExportArgv() async throws {
        let stub = StubProcessRunner()
        let backend = makeBackend(stub)
        try await backend.killContainer(id: "c1", signal: nil)
        XCTAssertEqual(stub.lastCall, ["kill", "c1"])
        try await backend.exportContainer(id: "c1", to: URL(fileURLWithPath: "/tmp/c1.tar"))
        XCTAssertEqual(stub.lastCall, ["export", "--output", "/tmp/c1.tar", "c1"])
    }

    func testPruneParsesReclaimedLine() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(
            exitCode: 0, stdout: "Reclaimed 12 MB in disk space\n", stderr: "")
        let result = try await makeBackend(stub).pruneContainers()
        XCTAssertEqual(result.reclaimedDescription, "Reclaimed 12 MB in disk space")
        XCTAssertEqual(stub.lastCall, ["prune"])
    }

    func testContainerStatsSnapshotArgvAndDecode() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(
            exitCode: 0, stdout: #"[{"id":"c1","cpuUsageUsec":5}]"#, stderr: "")
        let samples = try await makeBackend(stub).containerStats(ids: ["c1"])
        XCTAssertEqual(samples.first?.id, "c1")
        XCTAssertEqual(samples.first?.cpuUsageUsec, 5)
        XCTAssertEqual(stub.lastCall, ["stats", "--no-stream", "--format", "json", "c1"])
    }

    // MARK: - Streaming

    func testFollowLogsStreamsLinesAndBuildsArgv() async throws {
        let stub = StubProcessRunner()
        stub.streamLines = [
            OutputLine(source: .stdout, text: "booting"),
            OutputLine(source: .stdout, text: "ready"),
        ]

        var received: [String] = []
        for try await line in makeBackend(stub).followLogs(container: "c1") {
            received.append(line.text)
        }

        XCTAssertEqual(received, ["booting", "ready"])
        XCTAssertEqual(stub.lastCall, ["logs", "--follow", "c1"])
    }

    func testStreamRawStreamsLinesForArbitraryArgv() async throws {
        let stub = StubProcessRunner()
        stub.streamLines = [
            OutputLine(source: .stdout, text: "step 1/3"),
            OutputLine(source: .stderr, text: "warning"),
        ]

        var received: [OutputLine] = []
        for try await line in makeBackend(stub).streamRaw(["build", "--tag", "x", "."]) {
            received.append(line)
        }

        XCTAssertEqual(received.map(\.text), ["step 1/3", "warning"])
        XCTAssertEqual(received.last?.source, .stderr)
        XCTAssertEqual(stub.lastCall, ["build", "--tag", "x", "."])
    }

    func testPullImageStreamsProgressAndBuildsArgv() async throws {
        let stub = StubProcessRunner()
        stub.streamLines = [
            OutputLine(source: .stdout, text: "Pulling"),
            OutputLine(source: .stdout, text: "Done"),
        ]

        var received: [String] = []
        for try await line in makeBackend(stub).pullImage(reference: "alpine") {
            received.append(line.text)
        }

        XCTAssertEqual(received, ["Pulling", "Done"])
        XCTAssertEqual(stub.lastCall, ["image", "pull", "alpine"])
    }

    func testInspectImageDecodesValueAndRetainsRaw() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: Fixture.text("images-ls"), stderr: "")

        let parsed = try await makeBackend(stub)
            .inspectImage(reference: "docker.io/library/alpine:latest")

        XCTAssertEqual(parsed.value?.reference, "docker.io/library/alpine:latest")
        XCTAssertFalse(parsed.raw.isEmpty)
        XCTAssertEqual(
            stub.lastCall,
            ["image", "inspect", "docker.io/library/alpine:latest"]
        )
    }

    func testRemoveImageIssuesCorrectArgv() async throws {
        let stub = StubProcessRunner()

        try await makeBackend(stub).removeImage(reference: "alpine")

        XCTAssertEqual(stub.lastCall, ["image", "delete", "alpine"])
    }
}
