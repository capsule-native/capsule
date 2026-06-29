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
        XCTAssertEqual(
            alpine.digest,
            "sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b",
            "the full descriptor digest is carried for digest-centric copy actions")
        XCTAssertEqual(alpine.createdAt, "2026-06-16T00:00:15Z")
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

    func testParseContainersPopulatesVolumeMountsAndNetworkNames() throws {
        // Pins the real JSON keys against containers-with-mounts.json — a real
        // `container list -a --format json` capture of a container mounting a named
        // volume and attached to a user network (see Fixtures/README.md). `.contains`
        // (not exact equality) keeps the assertion robust to the runtime's exact
        // attachment order/set while still proving the keys decode.
        let rows = try OutputParser.parseContainers(Fixture.data("containers-with-mounts"))
        let fx = try XCTUnwrap(
            rows.first(where: { $0.name == "capsule-fx" }),
            "the throwaway capsule-fx container must be present in the fixture")
        XCTAssertTrue(
            fx.volumeMounts.contains("capsule-fx-vol"),
            "configuration.mounts[].type.volume.name must map to volumeMounts; got \(fx.volumeMounts)"
        )
        XCTAssertTrue(
            fx.networkNames.contains("capsule-fx-net"),
            "configuration.networks[].network must map to networkNames; got \(fx.networkNames)")
    }

    func testParseContainersDefaultsAttachmentsToEmptyWhenAbsent() throws {
        let json = """
            [{"id":"abc","configuration":{"id":"web",\
            "image":{"reference":"r"}},\
            "status":{"state":"running","networks":[]}}]
            """
        let rows = try OutputParser.parseContainers(Data(json.utf8))
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.volumeMounts, [])
        XCTAssertEqual(row.networkNames, [])
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

    // MARK: - Networks (M8 enrichment)

    func testParsesRealNetworkListIntoRowsWithBuiltinMarker() throws {
        let rows = try OutputParser.parseNetworks(Fixture.data("network-ls"))

        let network = try XCTUnwrap(rows.first)
        XCTAssertEqual(network.id, "default")
        XCTAssertEqual(network.name, "default")
        XCTAssertEqual(network.mode, "nat")
        XCTAssertEqual(network.gateway, "192.168.64.1")
        XCTAssertEqual(network.subnet, "192.168.64.0/24")
        XCTAssertEqual(network.plugin, "container-network-vmnet")
        XCTAssertEqual(network.ipv6Subnet, "fdb6:5eb:8ee:85cf::/64")
        XCTAssertTrue(network.isBuiltin, "the resource.role:builtin label marks it protected")
        XCTAssertEqual(network.labels["com.apple.container.resource.role"], "builtin")
    }

    func testParsesNetworkInspectAsNonBuiltin() throws {
        let rows = try OutputParser.parseNetworks(Fixture.data("network-inspect"))

        let network = try XCTUnwrap(rows.first)
        XCTAssertEqual(network.name, "capsule-m8-net")
        XCTAssertEqual(network.subnet, "10.88.0.0/24")
        XCTAssertEqual(network.gateway, "10.88.0.1")
        XCTAssertEqual(network.ipv6Subnet, "fd65:1ffc:2bce:b6aa::/64")
        XCTAssertFalse(network.isBuiltin, "a user-created network is not builtin")
        XCTAssertEqual(network.labels["tier"], "test")
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
            Data(#"[{"id":"default","status":"running"}]"#.utf8)
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

    // MARK: - Volumes (M8 enrichment)

    func testParsesRealVolumeListWithMetadata() throws {
        let rows = try OutputParser.parseVolumes(Fixture.data("volume-ls"))

        XCTAssertEqual(rows.count, 1)
        let volume = try XCTUnwrap(rows.first)
        XCTAssertEqual(volume.name, "capsule-m8-probe")
        XCTAssertEqual(volume.sizeBytes, 536_870_912)
        XCTAssertEqual(volume.options["size"], "512M")
        XCTAssertEqual(volume.labels["role"], "scratch")
        XCTAssertEqual(volume.createdAt, "2026-06-29T07:15:32Z")
        XCTAssertEqual(volume.source?.hasSuffix("capsule-m8-probe/volume.img"), true)
    }

    func testParsesVolumeInspectPayload() throws {
        let rows = try OutputParser.parseVolumes(Fixture.data("volume-inspect"))
        XCTAssertEqual(rows.first?.name, "capsule-m8-probe")
        XCTAssertEqual(rows.first?.sizeBytes, 536_870_912)
    }

    // MARK: - DNS (M8)

    func testParsesDNSDomains() throws {
        // Real `container system dns list --format json` shape: an array of bare
        // domain-name strings (the fixture is a live capture).
        let rows = try OutputParser.parseDNS(Fixture.data("dns-ls"))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.domain, "test")
        XCTAssertNil(rows.first?.localhostIP, "the list output carries only names, no localhost IP")
        XCTAssertEqual(rows.first?.id, "test")
    }

    /// The real `container system dns list --format json` emits an array of bare
    /// domain-name STRINGS, e.g. `["test","app.local"]` — not objects. (Verified live.)
    func testParsesDNSDomainsFromBareStringArray() throws {
        let rows = try OutputParser.parseDNS(Data(#"["test","app.local"]"#.utf8))
        XCTAssertEqual(rows.map(\.domain), ["test", "app.local"])
        XCTAssertNil(rows.first?.localhostIP)
    }

    func testParsesEmptyDNSList() throws {
        XCTAssertEqual(try OutputParser.parseDNS(Data("[]".utf8)).count, 0)
    }

    /// Drift tolerance: also accept an object form, in case a future CLI build adds detail.
    func testParseDNSAcceptsDomainAndNameFallbackKeys() throws {
        let byDomain = try OutputParser.parseDNS(Data(#"[{"domain":"a.test"}]"#.utf8))
        XCTAssertEqual(byDomain.first?.domain, "a.test")
        let byName = try OutputParser.parseDNS(Data(#"[{"name":"b.test"}]"#.utf8))
        XCTAssertEqual(byName.first?.domain, "b.test")
    }

    // MARK: - System df

    func testParseDiskUsageSplitsCountsFromBytes() throws {
        let usage = try OutputParser.parseDiskUsage(Fixture.data("system-df"))
        XCTAssertEqual(usage.images.total, 4)
        XCTAssertEqual(usage.images.active, 1)
        XCTAssertEqual(usage.images.sizeInBytes, 1_302_421_504)
        XCTAssertEqual(usage.images.reclaimable, 974_934_016)
        XCTAssertEqual(usage.images.inUseBytes, 1_302_421_504 - 974_934_016)
        XCTAssertEqual(usage.containers.total, 1)
        XCTAssertEqual(usage.volumes.sizeInBytes, 0)
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

    func testParseComponentVersionsReadsArray() throws {
        let comps = try OutputParser.parseComponentVersions(Fixture.data("system-version"))
        XCTAssertEqual(comps.count, 2)
        XCTAssertEqual(comps[0].appName, "container")
        XCTAssertEqual(comps[0].version, "1.0.0")
        XCTAssertEqual(comps[0].buildType, "release")
        XCTAssertTrue(comps[1].appName.contains("apiserver"))
        // The apiserver's messy full version string must be preserved verbatim, not cleaned.
        XCTAssertEqual(
            comps[1].version,
            "container-apiserver version 1.0.0 (build: release, commit: ee848e3)")
    }
}
