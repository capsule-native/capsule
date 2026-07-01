//
//  NetworkActionsModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The synchronous network operations: draft validation (required name + subnet-conflict),
//  the Create-sheet validity accessors (commandPreview/subnetConflictMessage/canCreate),
//  create/delete/prune success+failure surfacing, and the builtin-excluding prune preview.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class NetworkActionsModelTests: XCTestCase {
    private func model(
        _ backend: MockBackend, reload: @escaping () -> Void = {}
    )
        -> NetworkActionsModel
    {
        NetworkActionsModel(backend: backend, reloadList: { reload() })
    }

    // MARK: Validation

    func testValidatedConfigurationBuildsArgvInOrder() {
        let draft = NetworkDraft(
            name: "  app-net  ", subnet: "10.10.0.0/24", subnetV6: "fd00::/64",
            isInternal: true,
            options: [KeyValueRow(key: "mtu", value: "1400")],
            labels: [KeyValueRow(key: "team", value: "infra"), KeyValueRow()],
            plugin: "container-network-vmnet")

        guard
            case let .success(config) =
                model(MockBackend()).validatedConfiguration(draft, against: [])
        else {
            return XCTFail("a valid draft must produce a configuration")
        }

        XCTAssertEqual(config.name, "app-net", "name is trimmed")
        XCTAssertEqual(
            config.arguments,
            [
                "network", "create", "--internal", "--label", "team=infra",
                "--option", "mtu=1400", "--plugin", "container-network-vmnet",
                "--subnet", "10.10.0.0/24", "--subnet-v6", "fd00::/64", "app-net",
            ])
    }

    func testValidatedConfigurationRejectsEmptyName() {
        let result = model(MockBackend()).validatedConfiguration(
            NetworkDraft(name: "   "), against: [])
        guard case let .failure(.invalidInput(field, _)) = result else {
            return XCTFail("an empty name must fail validation")
        }
        XCTAssertEqual(field, "name")
    }

    func testValidatedConfigurationDetectsSubnetConflict() {
        let existing = [
            Network(
                summary: NetworkSummary(
                    id: "default", name: "default",
                    subnet: "192.168.64.0/24", isBuiltin: true))
        ]
        let result = model(MockBackend()).validatedConfiguration(
            NetworkDraft(name: "dup", subnet: "192.168.64.0/24"), against: existing)
        guard case let .failure(.invalidInput(field, message)) = result else {
            return XCTFail("an overlapping subnet must fail validation")
        }
        XCTAssertEqual(field, "subnet")
        XCTAssertTrue(message.contains("default"), "the conflict names the existing network")
    }

    // MARK: Create-sheet validity accessors

    func testCanCreateRequiresNameAndNoConflict() {
        let existing = [
            Network(
                summary: NetworkSummary(
                    id: "default", name: "default",
                    subnet: "192.168.64.0/24", isBuiltin: true))
        ]
        let m = model(MockBackend())
        XCTAssertFalse(m.canCreate(NetworkDraft(name: "   "), against: existing), "empty name")
        XCTAssertFalse(
            m.canCreate(NetworkDraft(name: "dup", subnet: "192.168.64.0/24"), against: existing),
            "a subnet conflict blocks Create")
        XCTAssertTrue(
            m.canCreate(NetworkDraft(name: "ok", subnet: "10.0.0.0/24"), against: existing))
    }

    func testSubnetConflictMessageNamesExistingNetworkAndAllowsEmpty() {
        let existing = [
            Network(
                summary: NetworkSummary(
                    id: "default", name: "default",
                    subnet: "192.168.64.0/24"))
        ]
        let m = model(MockBackend())
        let message = m.subnetConflictMessage(
            for: NetworkDraft(name: "dup", subnet: "192.168.64.0/24"), against: existing)
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("default") ?? false)
        XCTAssertNil(
            m.subnetConflictMessage(for: NetworkDraft(name: "ok", subnet: ""), against: existing),
            "an empty subnet is allowed (the runtime auto-assigns)")
    }

    /// TDD (Item 3): An IPv6 subnet overlap must also block creation.
    func testSubnetV6ConflictBlocksCreate() {
        let existing = [
            Network(
                summary: NetworkSummary(
                    id: "existing", name: "existing",
                    ipv6Subnet: "fd00::/64"))
        ]
        let draft = NetworkDraft(name: "new-net", subnetV6: "fd00::/64")
        let m = model(MockBackend())

        XCTAssertFalse(m.canCreate(draft, against: existing), "IPv6 overlap must block create")
        XCTAssertNotNil(
            m.subnetConflictMessage(for: draft, against: existing),
            "subnetConflictMessage must be non-nil for IPv6 overlap")
    }

    // MARK: Create

    func testCreateSucceedsReloadsAndClearsNotice() async {
        var reloads = 0
        let model = model(MockBackend(), reload: { reloads += 1 })

        let ok = await model.create(NetworkConfiguration(name: "br0"))

        XCTAssertTrue(ok)
        XCTAssertEqual(reloads, 1)
        XCTAssertNil(model.notice)
        XCTAssertTrue(model.busy.isEmpty)
    }

    func testCreateFailureSetsNoticeAndReturnsFalse() async {
        let backend = MockBackend()
        backend.failure = BackendError.nonZeroExit(
            command: "container network create", code: 1, stderr: "subnet overlaps existing")
        let model = model(backend)

        let ok = await model.create(NetworkConfiguration(name: "br0"))

        XCTAssertFalse(ok)
        XCTAssertNotNil(model.notice)
    }

    func testCreateFromDraftValidatesThenCreates() async {
        var reloads = 0
        let model = model(MockBackend(), reload: { reloads += 1 })

        let ok = await model.create(draft: NetworkDraft(name: "br0"), against: [])

        XCTAssertTrue(ok)
        XCTAssertEqual(reloads, 1)
    }

    func testCreateFromInvalidDraftSurfacesNoticeWithoutBackendCall() async {
        var reloads = 0
        let model = model(MockBackend(), reload: { reloads += 1 })

        let ok = await model.create(draft: NetworkDraft(name: "   "), against: [])

        XCTAssertFalse(ok)
        XCTAssertNotNil(model.notice, "validation failure surfaces as a notice")
        XCTAssertEqual(reloads, 0, "an invalid draft never reaches the backend")
    }

    func testCommandPreviewReflectsDraft() {
        let preview = model(MockBackend()).commandPreview(
            for: NetworkDraft(name: "br0", subnet: "10.0.0.0/24", isInternal: true))
        XCTAssertTrue(preview.hasPrefix("container network create"))
        XCTAssertTrue(preview.contains("--internal"))
        XCTAssertTrue(preview.contains("--subnet 10.0.0.0/24"))
        XCTAssertTrue(preview.hasSuffix("br0"))
    }

    // MARK: Delete / prune

    func testDeleteReloadsOnSuccess() async {
        var reloads = 0
        let model = model(
            MockBackend(networks: [NetworkSummary(id: "br0", name: "br0")]),
            reload: { reloads += 1 })

        await model.delete(name: "br0")

        XCTAssertEqual(reloads, 1)
        XCTAssertNil(model.notice)
    }

    func testDeleteFailureSetsNotice() async {
        let backend = MockBackend(networks: [NetworkSummary(id: "br0", name: "br0")])
        backend.failure = BackendError.nonZeroExit(
            command: "container network delete", code: 1, stderr: "network in use")
        let model = model(backend)

        await model.delete(name: "br0")

        XCTAssertNotNil(model.notice)
    }

    func testPruneReturnsSummaryAndReloads() async {
        var reloads = 0
        let model = model(MockBackend(), reload: { reloads += 1 })

        let summary = await model.prune()

        XCTAssertFalse(summary.message.isEmpty)
        XCTAssertEqual(reloads, 1)
    }

    func testComputePruneTargetsExcludesBuiltinAndConnected() async {
        let backend = MockBackend(
            containers: [
                ContainerSummary(
                    id: "c", name: "web", image: "alpine:latest", state: "running",
                    networkNames: ["app-net"])
            ],
            networks: [
                NetworkSummary(id: "default", name: "default", isBuiltin: true),
                NetworkSummary(id: "app-net", name: "app-net"),
                NetworkSummary(id: "idle", name: "idle"),
            ])
        let model = model(backend)

        let targets = await model.computePruneTargets()

        XCTAssertEqual(
            targets.map(\.name), ["idle"],
            "builtin is protected and a connected network is not a prune candidate")
    }

    func testNetworkCommandInvocationDrivesPreview() {
        let m = NetworkActionsModel(backend: MockBackend())
        var draft = NetworkDraft()
        draft.name = "app-net"
        XCTAssertEqual(m.commandPreview(for: draft), m.commandInvocation(for: draft).displayString)
        XCTAssertTrue(m.commandPreview(for: draft).hasPrefix("container network create"))
        XCTAssertEqual(m.pruneInvocation.rawDisplay, "container network prune")
    }
}
