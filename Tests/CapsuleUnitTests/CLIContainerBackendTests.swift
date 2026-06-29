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

    func testImageMaintenanceCommandsIssueCorrectArgv() async throws {
        let stub = StubProcessRunner()
        let backend = makeBackend(stub)

        try await backend.saveImage(
            references: ["alpine:latest"], to: URL(fileURLWithPath: "/tmp/a.tar"), platform: nil)
        XCTAssertEqual(stub.lastCall, ["image", "save", "--output", "/tmp/a.tar", "alpine:latest"])

        try await backend.loadImage(from: URL(fileURLWithPath: "/tmp/a.tar"))
        XCTAssertEqual(stub.lastCall, ["image", "load", "--input", "/tmp/a.tar"])

        try await backend.tagImage(source: "alpine:latest", target: "ghcr.io/me/alpine:1")
        XCTAssertEqual(stub.lastCall, ["image", "tag", "alpine:latest", "ghcr.io/me/alpine:1"])

        stub.result = CommandResult(exitCode: 0, stdout: "Reclaimed 5 MB in disk space", stderr: "")
        let pruned = try await backend.pruneImages(all: true)
        XCTAssertEqual(stub.lastCall, ["image", "prune", "--all"])
        XCTAssertEqual(pruned.reclaimedDescription, "Reclaimed 5 MB in disk space")
    }

    func testPushImageStreamsAndBuildsArgv() async throws {
        let stub = StubProcessRunner()
        stub.streamLines = [OutputLine(source: .stdout, text: "Pushing")]

        var received: [String] = []
        for try await line in makeBackend(stub).pushImage(
            reference: "ghcr.io/me/app:1", platform: "linux/amd64")
        {
            received.append(line.text)
        }

        XCTAssertEqual(received, ["Pushing"])
        XCTAssertEqual(
            stub.lastCall, ["image", "push", "--platform", "linux/amd64", "ghcr.io/me/app:1"])
    }

    // MARK: - Registry credential safety

    /// The defining secret-safety guarantee: the password reaches the CLI through stdin,
    /// and NEVER appears anywhere in the argument vector.
    func testRegistryLoginFeedsSecretThroughStdinNotArgv() async throws {
        let stub = StubProcessRunner()

        try await makeBackend(stub).registryLogin(
            server: "ghcr.io", username: "me", password: "sup3r-s3cret")

        XCTAssertEqual(
            stub.lastCall, ["registry", "login", "--username", "me", "--password-stdin", "ghcr.io"])
        XCTAssertFalse(
            stub.lastCall?.contains("sup3r-s3cret") ?? false,
            "the password must never appear on argv")
        XCTAssertEqual(
            stub.lastStandardInput, "sup3r-s3cret", "the password is delivered via stdin")
    }

    func testRegistryTestAlsoUsesStdinAndDoesNotLeakOnArgv() async throws {
        let stub = StubProcessRunner()

        try await makeBackend(stub).registryTest(
            server: "ghcr.io", username: nil, password: "another-secret")

        XCTAssertEqual(stub.lastCall, ["registry", "login", "--password-stdin", "ghcr.io"])
        XCTAssertFalse(stub.lastCall?.contains("another-secret") ?? false)
        XCTAssertEqual(stub.lastStandardInput, "another-secret")
    }

    func testRegistryLogoutBuildsArgv() async throws {
        let stub = StubProcessRunner()
        try await makeBackend(stub).registryLogout(server: "ghcr.io")
        XCTAssertEqual(stub.lastCall, ["registry", "logout", "ghcr.io"])
    }

    // MARK: - M7: run / build / copy / logs / listDirectory

    func testRunContainerReturnsParsedIDAndBuildsArgv() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: "abc123def\n", stderr: "")
        let id = try await makeBackend(stub).runContainer(
            RunConfiguration(image: "nginx", detach: true))
        XCTAssertEqual(id, "abc123def")
        XCTAssertEqual(stub.lastCall, ["run", "-d", "nginx"])
    }

    func testRunContainerTakesLastStdoutLineAsID() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(
            exitCode: 0, stdout: "pulling image\nstarting\nc0ffee01\n", stderr: "")
        let id = try await makeBackend(stub).runContainer(RunConfiguration(image: "img"))
        XCTAssertEqual(id, "c0ffee01")
    }

    func testBuildImageStreamsAndBuildsArgv() async throws {
        let stub = StubProcessRunner()
        stub.streamLines = [OutputLine(source: .stdout, text: "Step 1/2")]
        var got: [String] = []
        for try await line in makeBackend(stub).buildImage(
            BuildConfiguration(contextDirectory: URL(fileURLWithPath: "/p"), tag: "t:1"))
        {
            got.append(line.text)
        }
        XCTAssertEqual(got, ["Step 1/2"])
        XCTAssertEqual(stub.lastCall, ["build", "--tag", "t:1", "/p"])
    }

    func testCopyToContainerComposesEndpointAndBuildsArgv() async throws {
        let stub = StubProcessRunner()
        try await makeBackend(stub).copyToContainer(
            source: URL(fileURLWithPath: "/local/file.txt"), containerID: "c1",
            containerPath: "/app/file.txt")
        XCTAssertEqual(stub.lastCall, ["copy", "/local/file.txt", "c1:/app/file.txt"])
    }

    func testCopyFromContainerComposesEndpointAndBuildsArgv() async throws {
        let stub = StubProcessRunner()
        try await makeBackend(stub).copyFromContainer(
            containerID: "c1", containerPath: "/app/file.txt",
            destination: URL(fileURLWithPath: "/local/file.txt"))
        XCTAssertEqual(stub.lastCall, ["copy", "c1:/app/file.txt", "/local/file.txt"])
    }

    func testFetchLogsSplitsStdoutAndBuildsArgv() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: "line one\nline two", stderr: "")
        let lines = try await makeBackend(stub).fetchLogs(container: "c1", tail: 50, boot: false)
        XCTAssertEqual(lines.map(\.text), ["line one", "line two"])
        XCTAssertEqual(stub.lastCall, ["logs", "-n", "50", "c1"])
    }

    func testFetchLogsDropsTrailingNewline() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: "a\nb\n", stderr: "")
        let lines = try await makeBackend(stub).fetchLogs(container: "c1", tail: nil, boot: false)
        XCTAssertEqual(lines.map(\.text), ["a", "b"])  // no spurious blank final line

        stub.result = CommandResult(exitCode: 0, stdout: "", stderr: "")
        let empty = try await makeBackend(stub).fetchLogs(container: "c1", tail: nil, boot: false)
        XCTAssertTrue(empty.isEmpty)
    }

    func testListDirectoryParsesLsLeniently() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(
            exitCode: 0,
            stdout: """
                total 8
                drwxr-xr-x 2 root root 4096 Jun 1 00:00 bin
                -rw-r--r-- 1 root root 220 Jun 1 00:00 .bashrc
                lrwxrwxrwx 1 root root 7 Jun 1 00:00 sh -> busybox
                """, stderr: "")
        let rows = try await makeBackend(stub).listContainerDirectory(id: "c1", path: "/")
        XCTAssertEqual(stub.lastCall, ["exec", "c1", "ls", "-la", "/"])
        XCTAssertTrue(rows.contains { $0.name == "bin" && $0.isDirectory && $0.size == 4096 })
        XCTAssertTrue(rows.contains { $0.name == ".bashrc" && !$0.isDirectory })
        XCTAssertTrue(rows.contains { $0.name == "sh" && !$0.isDirectory })
    }

    func testListDirectoryThrowsOnNonZeroExit() async {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 1, stdout: "", stderr: "no such file or directory")
        do {
            _ = try await makeBackend(stub).listContainerDirectory(id: "c1", path: "/nope")
            XCTFail("expected a thrown error on non-zero exit")
        } catch let BackendError.nonZeroExit(_, code, stderr) {
            XCTAssertEqual(code, 1)
            XCTAssertTrue(stderr.contains("no such file"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - M8: volumes / networks / DNS

    func testInspectVolumeDecodesFixtureAndBuildsArgvWithoutFormat() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: Fixture.text("volume-inspect"), stderr: "")
        let parsed = try await makeBackend(stub).inspectVolume(names: ["capsule-m8-probe"])
        XCTAssertEqual(parsed.value?.first?.name, "capsule-m8-probe")
        XCTAssertEqual(parsed.value?.first?.sizeBytes, 536_870_912)
        XCTAssertFalse(parsed.raw.isEmpty)
        XCTAssertEqual(stub.lastCall, ["volume", "inspect", "capsule-m8-probe"])
    }

    func testCreateVolumeBuildsArgvFromConfig() async throws {
        let stub = StubProcessRunner()
        try await makeBackend(stub).createVolume(
            VolumeConfiguration(name: "data", size: "1G", labels: ["env=dev"]))
        XCTAssertEqual(
            stub.lastCall, ["volume", "create", "--label", "env=dev", "-s", "1G", "data"])
    }

    func testDeleteVolumesBuildsArgv() async throws {
        let stub = StubProcessRunner()
        try await makeBackend(stub).deleteVolumes(names: ["a", "b"])
        XCTAssertEqual(stub.lastCall, ["volume", "delete", "a", "b"])
    }

    func testPruneVolumesParsesReclaimedAndOnlyNonZeroExitFails() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(
            exitCode: 0, stdout: "Reclaimed 3 MB in disk space\n", stderr: "noise")
        let result = try await makeBackend(stub).pruneVolumes()
        XCTAssertEqual(result.reclaimedDescription, "Reclaimed 3 MB in disk space")
        XCTAssertEqual(stub.lastCall, ["volume", "prune"])

        stub.result = CommandResult(exitCode: 1, stdout: "", stderr: "boom")
        do {
            _ = try await makeBackend(stub).pruneVolumes()
            XCTFail("expected non-zero exit to throw")
        } catch let BackendError.nonZeroExit(_, code, stderr) {
            XCTAssertEqual(code, 1)
            XCTAssertEqual(stderr, "boom")
        }
    }

    func testInspectNetworkDecodesFixtureAndBuildsArgv() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(
            exitCode: 0, stdout: Fixture.text("network-inspect"), stderr: "")
        let parsed = try await makeBackend(stub).inspectNetwork(names: ["capsule-m8-net"])
        XCTAssertEqual(parsed.value?.first?.name, "capsule-m8-net")
        XCTAssertEqual(parsed.value?.first?.isBuiltin, false)
        XCTAssertEqual(stub.lastCall, ["network", "inspect", "capsule-m8-net"])
    }

    func testCreateAndDeleteNetworkBuildArgv() async throws {
        let stub = StubProcessRunner()
        let backend = makeBackend(stub)
        try await backend.createNetwork(
            NetworkConfiguration(name: "app-net", subnet: "10.0.0.0/24"))
        XCTAssertEqual(stub.lastCall, ["network", "create", "--subnet", "10.0.0.0/24", "app-net"])
        try await backend.deleteNetworks(names: ["app-net"])
        XCTAssertEqual(stub.lastCall, ["network", "delete", "app-net"])
    }

    func testPruneNetworksParsesReclaimed() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: "Reclaimed 0 B in disk space", stderr: "")
        let result = try await makeBackend(stub).pruneNetworks()
        XCTAssertEqual(result.reclaimedDescription, "Reclaimed 0 B in disk space")
        XCTAssertEqual(stub.lastCall, ["network", "prune"])
    }

    func testListDNSDomainsDecodesFixtureAndBuildsArgv() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(exitCode: 0, stdout: Fixture.text("dns-ls"), stderr: "")
        let domains = try await makeBackend(stub).listDNSDomains()
        XCTAssertEqual(domains.map(\.domain), ["test"])
        XCTAssertNil(
            domains.first?.localhostIP, "the list output carries only names, no localhost IP")
        XCTAssertEqual(stub.lastCall, ["system", "dns", "list", "--format", "json"])
    }

    // MARK: - M10: system df

    func testSystemDiskUsageArgvAndDecode() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(
            exitCode: 0,
            stdout: String(decoding: Fixture.data("system-df"), as: UTF8.self),
            stderr: "")
        let backend = CLIContainerBackend(
            executableURL: URL(fileURLWithPath: "/usr/bin/container"), runner: stub)
        let usage = try await backend.systemDiskUsage()
        XCTAssertEqual(stub.lastCall, ["system", "df", "--format", "json"])
        XCTAssertEqual(usage.images.total, 4)
    }

    // MARK: - M10: system version component list

    func testSystemComponentVersionsArgvAndDecode() async throws {
        let stub = StubProcessRunner()
        stub.result = CommandResult(
            exitCode: 0,
            stdout: String(decoding: Fixture.data("system-version"), as: UTF8.self),
            stderr: "")
        let backend = CLIContainerBackend(
            executableURL: URL(fileURLWithPath: "/usr/bin/container"), runner: stub)
        let comps = try await backend.systemComponentVersions()
        XCTAssertEqual(stub.lastCall, ["system", "version", "--format", "json"])
        XCTAssertEqual(comps.count, 2)
    }
}
