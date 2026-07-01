//
//  VolumeActionsModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The synchronous volume operations: create/delete/prune (busy set + LifecycleNotice on
//  failure, reloadList on success, no Activity tasks), the zero-attachment prune preview,
//  draft validation, and the Domain-primitive accessors (commandPreview / validationMessage /
//  isValid / create(draft:)) the create sheet binds to.

import CapsuleBackend
import CapsuleDiagnostics
import XCTest

@testable import CapsuleDomain

@MainActor
final class VolumeActionsModelTests: XCTestCase {
    func testCreateSucceedsReloadsAndReturnsTrue() async {
        let backend = MockBackend(volumes: [])
        var reloads = 0
        let model = VolumeActionsModel(backend: backend, reloadList: { reloads += 1 })

        let ok = await model.create(VolumeConfiguration(name: "data"))

        XCTAssertTrue(ok)
        XCTAssertEqual(reloads, 1)
        XCTAssertNil(model.notice)
        XCTAssertTrue(model.busy.isEmpty, "busy clears after the op")
    }

    func testCreateFailureSetsNoticeAndReturnsFalse() async {
        let backend = MockBackend(volumes: [])
        backend.failure = BackendError.nonZeroExit(
            command: "container volume create", code: 1, stderr: "name already in use")
        let model = VolumeActionsModel(
            backend: backend, normalize: { ErrorNormalizer.normalize($0) })

        let ok = await model.create(VolumeConfiguration(name: "data"))

        XCTAssertFalse(ok)
        XCTAssertNotNil(model.notice)
        XCTAssertTrue(model.busy.isEmpty)
    }

    func testDeleteReloadsAndClearsBusy() async {
        let backend = MockBackend(volumes: [VolumeSummary(name: "data")])
        var reloads = 0
        let model = VolumeActionsModel(backend: backend, reloadList: { reloads += 1 })

        await model.delete(name: "data")

        XCTAssertEqual(reloads, 1)
        XCTAssertNil(model.notice)
        XCTAssertTrue(model.busy.isEmpty)
    }

    func testDeleteFailureSurfacesNotice() async {
        let backend = MockBackend(volumes: [VolumeSummary(name: "data")])
        backend.failure = BackendError.nonZeroExit(
            command: "container volume delete", code: 1,
            stderr: "Error: failed to delete one or more volumes")
        let model = VolumeActionsModel(
            backend: backend, normalize: { ErrorNormalizer.normalize($0) })

        await model.delete(name: "data")

        XCTAssertNotNil(model.notice)
    }

    func testDeleteAllRunsAndReloads() async {
        let backend = MockBackend(volumes: [VolumeSummary(name: "a"), VolumeSummary(name: "b")])
        var reloads = 0
        let model = VolumeActionsModel(backend: backend, reloadList: { reloads += 1 })

        await model.deleteAll(names: ["a", "b"])

        XCTAssertEqual(reloads, 1)
        XCTAssertNil(model.notice)
    }

    func testPruneReturnsSummaryAndReloads() async {
        let backend = MockBackend(volumes: [VolumeSummary(name: "data")])
        var reloads = 0
        let model = VolumeActionsModel(backend: backend, reloadList: { reloads += 1 })

        let summary = await model.prune()

        XCTAssertFalse(summary.message.isEmpty)
        XCTAssertEqual(reloads, 1)
    }

    func testPruneFailureSetsNotice() async {
        let backend = MockBackend(volumes: [])
        backend.failure = BackendError.nonZeroExit(
            command: "container volume prune", code: 1, stderr: "boom")
        let model = VolumeActionsModel(backend: backend)

        let summary = await model.prune()

        XCTAssertNotNil(model.notice)
        XCTAssertEqual(summary.message, "Cleanup failed.")
    }

    func testComputePruneTargetsReturnsZeroAttachmentVolumes() async {
        let backend = MockBackend(
            containers: [
                ContainerSummary(
                    id: "c1", name: "web", image: "alpine", state: "running",
                    volumeMounts: ["data"])
            ],
            volumes: [VolumeSummary(name: "data"), VolumeSummary(name: "cache")])
        let model = VolumeActionsModel(backend: backend)

        let targets = await model.computePruneTargets()

        XCTAssertEqual(targets.map(\.name), ["cache"], "only unattached volumes are candidates")
    }

    func testValidatedConfigurationRequiresName() {
        let model = VolumeActionsModel(backend: MockBackend())
        guard case let .failure(error) = model.validatedConfiguration(VolumeDraft()) else {
            return XCTFail("an empty name must fail validation")
        }
        guard case let .invalidInput(field, _) = error else {
            return XCTFail("expected .invalidInput")
        }
        XCTAssertEqual(field, "name")
    }

    func testValidatedConfigurationRejectsBadSize() {
        let model = VolumeActionsModel(backend: MockBackend())
        let draft = VolumeDraft(name: "data", size: "10")
        guard case let .failure(error) = model.validatedConfiguration(draft),
            case let .invalidInput(field, _) = error
        else {
            return XCTFail("a suffixless size must fail validation")
        }
        XCTAssertEqual(field, "size")
    }

    func testValidatedConfigurationBuildsConfigWithOptionsAndLabels() {
        let model = VolumeActionsModel(backend: MockBackend())
        let draft = VolumeDraft(
            name: "data", size: "10G",
            options: [
                KeyValueRow(key: "journaling", value: "on"), KeyValueRow(key: "", value: "x"),
            ],
            labels: [KeyValueRow(key: "env", value: "dev")])

        guard case let .success(config) = model.validatedConfiguration(draft) else {
            return XCTFail("a valid draft must produce a configuration")
        }
        XCTAssertEqual(config.name, "data")
        XCTAssertEqual(config.size, "10G")
        XCTAssertEqual(config.options, ["journaling=on"], "blank-key rows are dropped")
        XCTAssertEqual(config.labels, ["env=dev"])
    }

    // MARK: - Domain-primitive accessors the sheet binds to

    func testCommandPreviewReflectsValidatedConfiguration() {
        let model = VolumeActionsModel(backend: MockBackend())
        let draft = VolumeDraft(
            name: "data", size: "10G",
            options: [KeyValueRow(key: "journaling", value: "on")],
            labels: [KeyValueRow(key: "env", value: "dev")])

        XCTAssertEqual(
            model.commandPreview(for: draft),
            "container volume create --label env=dev --opt journaling=on -s 10G data")
    }

    func testCommandPreviewFallsBackWhenInvalid() {
        let model = VolumeActionsModel(backend: MockBackend())
        XCTAssertEqual(model.commandPreview(for: VolumeDraft()), "container volume create")
    }

    /// TDD (Item 1): The preview must reflect entered fields even when the name is empty.
    /// Before the tolerant-helper fix this returned "container volume create" (collapsed).
    func testCommandPreviewIncludesFieldsEvenWithEmptyName() {
        let model = VolumeActionsModel(backend: MockBackend())
        let draft = VolumeDraft(
            name: "",  // invalid — name not yet entered
            size: "10G",
            labels: [KeyValueRow(key: "env", value: "dev")])

        let preview = model.commandPreview(for: draft)

        XCTAssertTrue(preview.contains("-s 10G"), "size must appear in preview even without a name")
        XCTAssertTrue(
            preview.contains("--label env=dev"),
            "label must appear in preview even without a name")
        XCTAssertNotEqual(
            preview, "container volume create",
            "preview must not collapse when fields are entered")
    }

    func testValidationMessageAndIsValidTrackValidity() {
        let model = VolumeActionsModel(backend: MockBackend())
        XCTAssertNil(model.validationMessage(VolumeDraft(name: "data")))
        XCTAssertTrue(model.isValid(VolumeDraft(name: "data")))
        XCTAssertNotNil(model.validationMessage(VolumeDraft()))
        XCTAssertFalse(model.isValid(VolumeDraft()))
    }

    func testCreateFromDraftValidatesAndSucceeds() async {
        let backend = MockBackend(volumes: [])
        var reloads = 0
        let model = VolumeActionsModel(backend: backend, reloadList: { reloads += 1 })

        let ok = await model.create(draft: VolumeDraft(name: "data", size: "10G"))

        XCTAssertTrue(ok)
        XCTAssertEqual(reloads, 1)
        XCTAssertNil(model.notice)
    }

    func testCreateFromDraftSetsNoticeOnValidationFailure() async {
        let backend = MockBackend(volumes: [])
        var reloads = 0
        let model = VolumeActionsModel(backend: backend, reloadList: { reloads += 1 })

        let ok = await model.create(draft: VolumeDraft())  // empty name

        XCTAssertFalse(ok)
        XCTAssertNotNil(model.notice)
        XCTAssertEqual(reloads, 0, "a validation failure never reaches the backend")
    }

    func testVolumeCommandInvocationDropsEmptyNameAndDrivesPreview() {
        let m = VolumeActionsModel(backend: MockBackend())
        var draft = VolumeDraft()
        draft.size = "10G"
        XCTAssertFalse(m.commandInvocation(for: draft).rawDisplay.hasSuffix(" "))
        XCTAssertEqual(m.commandPreview(for: draft), m.commandInvocation(for: draft).displayString)
        XCTAssertEqual(m.pruneInvocation.rawDisplay, "container volume prune")
    }
}
