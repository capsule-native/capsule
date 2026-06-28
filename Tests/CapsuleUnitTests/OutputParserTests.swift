//
//  OutputParserTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Exercises the structured-output decoders against real `container --format json`
//  captures (see Tests/CapsuleUnitTests/Fixtures) plus hand-built degraded payloads.

import CapsuleBackend
import XCTest

@testable import CapsuleCLIBackend

final class OutputParserTests: XCTestCase {
    // MARK: - Images

    func testParsesRealImageListIntoRows() throws {
        let rows = try OutputParser.parseImages(Fixture.data("images-ls"))

        XCTAssertEqual(rows.count, 1)
        let alpine = try XCTUnwrap(rows.first)
        XCTAssertEqual(alpine.reference, "docker.io/library/alpine:latest")
        XCTAssertEqual(
            alpine.id,
            "28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b"
        )
        XCTAssertEqual(alpine.sizeBytes, 9218)
    }

    func testParsesEmptyImageList() throws {
        XCTAssertEqual(try OutputParser.parseImages(Data("[]".utf8)).count, 0)
    }

    /// `container image inspect` emits the same array shape as `image list` (no `--format`
    /// flag). Decoding a real captured `inspect` payload guards the shared-decoder path.
    func testParsesRealImageInspectPayload() throws {
        let rows = try OutputParser.parseImages(Fixture.data("image-inspect"))

        XCTAssertEqual(rows.count, 1)
        let alpine = try XCTUnwrap(rows.first)
        XCTAssertEqual(alpine.reference, "docker.io/library/alpine:latest")
        XCTAssertEqual(alpine.sizeBytes, 9218)
    }

    func testParsePruneResultFindsReclaimedOnEitherStream() {
        let a = OutputParser.parsePruneResult(
            stdout: "Reclaimed 75 MB in disk space\n", stderr: "")
        XCTAssertEqual(a.reclaimedDescription, "Reclaimed 75 MB in disk space")
        let b = OutputParser.parsePruneResult(
            stdout: "", stderr: "Reclaimed Zero KB in disk space")
        XCTAssertEqual(b.reclaimedDescription, "Reclaimed Zero KB in disk space")
        let c = OutputParser.parsePruneResult(stdout: "noise", stderr: "")
        XCTAssertNil(c.reclaimedDescription)
        XCTAssertTrue(c.raw.contains("noise"))
    }

    // MARK: - Containers

    func testParseContainersExtractsCreationDate() throws {
        let json = """
            [{"id":"abc","configuration":{"id":"web",\
            "image":{"reference":"docker.io/library/alpine:latest"},\
            "creationDate":"2026-06-20T09:15:00Z"},\
            "status":{"state":"running","networks":[]}}]
            """
        let rows = try OutputParser.parseContainers(Data(json.utf8))
        XCTAssertEqual(rows.first?.createdAt, "2026-06-20T09:15:00Z")
    }

    func testParseStatsEmptyArray() throws {
        XCTAssertEqual(try OutputParser.parseStats(Data("[]".utf8)).count, 0)
    }

    func testParseStatsDecodesSampleAndIsLenient() throws {
        let json = """
            [{"id":"abc","cpuUsageUsec":1000000,"memoryUsageBytes":64000000,"numProcesses":3},
             {"id":"def"},
             {"noId":true}]
            """
        let rows = try OutputParser.parseStats(Data(json.utf8))
        XCTAssertEqual(rows.map(\.id), ["abc", "def"])  // 3rd dropped: missing required id
        XCTAssertEqual(rows.first?.cpuUsageUsec, 1_000_000)
        XCTAssertEqual(rows.first?.numProcesses, 3)
    }

    func testParsesContainerListIntoRows() throws {
        let rows = try OutputParser.parseContainers(Fixture.data("containers-ls"))

        XCTAssertEqual(rows.count, 2)

        let running = try XCTUnwrap(rows.first)
        XCTAssertEqual(running.image, "docker.io/library/alpine:latest")
        XCTAssertEqual(running.state, "running")
        XCTAssertEqual(running.ip, "192.168.64.3", "CIDR prefix length should be stripped")

        let stopped = rows[1]
        XCTAssertEqual(stopped.state, "stopped")
        XCTAssertNil(stopped.ip, "a container with no attachments has no IP")
    }

    func testParsesEmptyContainerList() throws {
        XCTAssertEqual(
            try OutputParser.parseContainers(Fixture.data("containers-ls-empty")).count, 0)
    }

    func testSkipsMalformedContainerRowsInsteadOfFailingWholeList() throws {
        // One valid element, one that no longer matches the schema (missing
        // `configuration`). The valid row must still come through.
        let json = Data(
            """
            [{"id":"ok","configuration":{"id":"ok","image":{"reference":"r"}},
              "status":{"state":"running","networks":[]}},
             {"id":"broken","status":{"state":"running","networks":[]}}]
            """.utf8
        )

        let rows = try OutputParser.parseContainers(json)

        XCTAssertEqual(rows.map(\.id), ["ok"])
    }

    func testThrowsDecodingFailedWhenTopLevelIsNotAnArray() {
        XCTAssertThrowsError(try OutputParser.parseContainers(Data(#"{"oops":true}"#.utf8))) {
            guard case BackendError.decodingFailed = $0 else {
                return XCTFail("expected BackendError.decodingFailed, got \($0)")
            }
        }
    }

    // MARK: - Networks

    func testParsesRealNetworkListIntoRows() throws {
        let rows = try OutputParser.parseNetworks(Fixture.data("network-ls"))

        let network = try XCTUnwrap(rows.first)
        XCTAssertEqual(network.id, "default")
        XCTAssertEqual(network.name, "default")
        XCTAssertEqual(network.mode, "nat")
        XCTAssertEqual(network.gateway, "192.168.64.1")
        XCTAssertEqual(network.subnet, "192.168.64.0/24")
    }

    // MARK: - Volumes / registries / machines / builder

    func testParsesRealEmptyCapturesAsEmptyLists() throws {
        XCTAssertEqual(try OutputParser.parseVolumes(Fixture.data("volume-ls-empty")).count, 0)
        XCTAssertEqual(try OutputParser.parseRegistries(Fixture.data("registry-ls")).count, 0)
        XCTAssertEqual(try OutputParser.parseMachines(Fixture.data("machine-ls")).count, 0)
    }

    func testParsesPopulatedVolumeAndMachineAndRegistry() throws {
        let volumes = try OutputParser.parseVolumes(
            Data(#"[{"name":"data","source":"/var/lib/x"}]"#.utf8)
        )
        XCTAssertEqual(volumes, [VolumeSummary(name: "data", source: "/var/lib/x")])

        let machines = try OutputParser.parseMachines(
            Data(#"[{"name":"default","state":"running"}]"#.utf8)
        )
        XCTAssertEqual(machines, [MachineSummary(name: "default", state: "running")])

        let registries = try OutputParser.parseRegistries(
            Data(#"[{"server":"ghcr.io"}]"#.utf8)
        )
        XCTAssertEqual(registries, [RegistrySummary(server: "ghcr.io")])
    }

    func testBuilderStatusReflectsRunningState() throws {
        XCTAssertFalse(
            try OutputParser.parseBuilderStatus(Fixture.data("builder-status")).isRunning,
            "no builder configured → not running"
        )
        XCTAssertTrue(
            try OutputParser.parseBuilderStatus(Data(#"[{"state":"running"}]"#.utf8)).isRunning
        )
    }

    // MARK: - Version

    func testParsesRealVersionWithClientAndServer() throws {
        let version = try OutputParser.parseVersion(Fixture.data("system-version"))

        XCTAssertEqual(version.client, "1.0.0")
        let server = try XCTUnwrap(version.server)
        XCTAssertTrue(server.contains("1.0.0"), "server version was \(server)")
    }

    func testParsesVersionWithClientOnlyLeavesServerNil() throws {
        let json = Data(#"[{"appName":"container","version":"1.2.3"}]"#.utf8)

        let version = try OutputParser.parseVersion(json)

        XCTAssertEqual(version.client, "1.2.3")
        XCTAssertNil(version.server)
    }
}
