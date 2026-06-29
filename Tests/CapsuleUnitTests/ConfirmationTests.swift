//
//  ConfirmationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class ConfirmationTests: XCTestCase {
    func testKillRequiresConfirmationOnlyForMultiple() {
        XCTAssertNil(ConfirmationRequest.kill(ids: ["a"]))  // single: no sheet
        XCTAssertNotNil(ConfirmationRequest.kill(ids: ["a", "b"]))  // bulk: sheet
    }

    func testDeleteAlwaysConfirmsAndCarriesForce() {
        let single = ConfirmationRequest.delete(ids: ["a"], anyRunning: false)
        XCTAssertNotNil(single)
        XCTAssertEqual(single?.kind, .delete(force: false))
        let running = ConfirmationRequest.delete(ids: ["a"], anyRunning: true)
        XCTAssertEqual(running?.kind, .delete(force: true))
        XCTAssertTrue(running?.message.localizedCaseInsensitiveContains("stop") ?? false)
    }

    func testExportNotStoppedConfirmation() {
        let r = ConfirmationRequest.exportNotStopped(id: "a")
        XCTAssertEqual(r.kind, .exportNotStopped)
        XCTAssertEqual(r.targetIDs, ["a"])
    }

    // MARK: - Images (M6)

    func testDeleteImageAlwaysConfirmsSingleAndBulk() {
        let single = ConfirmationRequest.deleteImage(ids: ["alpine:latest"])
        XCTAssertEqual(single?.kind, .deleteImage)
        XCTAssertEqual(single?.targetIDs, ["alpine:latest"])
        XCTAssertTrue(single?.title.localizedCaseInsensitiveContains("image") ?? false)

        let bulk = ConfirmationRequest.deleteImage(ids: ["a:1", "b:1"])
        XCTAssertTrue(bulk?.title.contains("2") ?? false)

        XCTAssertNil(ConfirmationRequest.deleteImage(ids: []), "nothing selected → no sheet")
    }

    // MARK: - Volumes (M8)

    func testDeleteVolumeWarnsDataLossAndCarriesKind() {
        let request = ConfirmationRequest.deleteVolume(
            names: ["data"], attachments: AttachmentIndex(volumes: [:], networks: [:]))
        XCTAssertEqual(request?.kind, .deleteVolume)
        XCTAssertEqual(request?.targetIDs, ["data"])
        XCTAssertEqual(
            request?.message, "Deleting data permanently destroys its data.",
            "an unattached volume warns about data loss only")
    }

    func testDeleteVolumeIncludesMountingContainers() {
        let index = AttachmentIndex(volumes: ["data": ["web", "db"]], networks: [:])
        let request = ConfirmationRequest.deleteVolume(names: ["data"], attachments: index)
        let message = request?.message ?? ""
        XCTAssertTrue(message.contains("permanently destroys its data."))
        XCTAssertTrue(message.contains("It is mounted by:"))
        XCTAssertTrue(message.contains("web"))
        XCTAssertTrue(message.contains("db"))
        XCTAssertTrue(message.contains("delete will fail until they are removed"))
    }

    func testDeleteVolumeNilForEmptySelection() {
        XCTAssertNil(
            ConfirmationRequest.deleteVolume(
                names: [], attachments: AttachmentIndex(volumes: [:], networks: [:])))
    }

    func testPruneVolumesConfirmation() {
        let request = ConfirmationRequest.pruneVolumes()
        XCTAssertEqual(request.kind, .pruneVolumes)
        XCTAssertTrue(request.message.localizedCaseInsensitiveContains("destroy"))
    }

    // MARK: - Networks (M8)

    func testDeleteNetworkReturnsNilForBuiltin() {
        let index = AttachmentIndex(volumes: [:], networks: [:])
        XCTAssertNil(
            ConfirmationRequest.deleteNetwork(
                name: "default", isBuiltin: true, attachments: index),
            "builtin networks are protected — no confirmation, Delete disabled in the UI")
    }

    func testDeleteNetworkConfirmsAndNamesConnectedContainers() {
        let index = AttachmentIndex(volumes: [:], networks: ["app-net": ["web", "db"]])
        let request = ConfirmationRequest.deleteNetwork(
            name: "app-net", isBuiltin: false, attachments: index)
        XCTAssertEqual(request?.kind, .deleteNetwork)
        XCTAssertEqual(request?.targetIDs, ["app-net"])
        XCTAssertTrue(request?.message.contains("app-net") ?? false)
        XCTAssertTrue(request?.message.contains("web") ?? false, "connected containers are named")
    }

    func testDeleteNetworkWithoutConnectionsOmitsTheList() {
        let index = AttachmentIndex(volumes: [:], networks: [:])
        let request = ConfirmationRequest.deleteNetwork(
            name: "idle", isBuiltin: false, attachments: index)
        XCTAssertNotNil(request)
        XCTAssertFalse(request?.message.contains("Connected containers") ?? true)
    }

    func testPruneNetworksConfirmation() {
        let request = ConfirmationRequest.pruneNetworks()
        XCTAssertEqual(request.kind, .pruneNetworks)
        XCTAssertTrue(request.targetIDs.isEmpty)
    }
}
