//
//  ImageActionsModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The non-streaming image operations: tag, delete (single/bulk, idempotent not-found, and
//  dependency-conflict surfacing), and prune (target preview + result).

import CapsuleBackend
import CapsuleDiagnostics
import XCTest

@testable import CapsuleDomain

@MainActor
final class ImageActionsModelTests: XCTestCase {
    private func img(_ ref: String, digest: String = "sha256:a") -> ImageSummary {
        ImageSummary(id: digest, reference: ref, sizeBytes: 1, digest: digest)
    }

    func testTagSucceedsReloadsAndLogs() async {
        let backend = MockBackend(images: [img("alpine:latest")])
        var reloads = 0
        let model = ImageActionsModel(backend: backend, reloadList: { reloads += 1 })

        let ok = await model.tag(source: "alpine:latest", target: "alpine:pinned")

        XCTAssertTrue(ok)
        XCTAssertEqual(backend.lastTag?.target, "alpine:pinned")
        XCTAssertEqual(reloads, 1)
        XCTAssertNil(model.notice)
    }

    func testTagFailureSetsNoticeAndReturnsFalse() async {
        let backend = MockBackend(images: [img("alpine:latest")])
        backend.failure = BackendError.nonZeroExit(
            command: "container image tag", code: 1, stderr: "invalid reference")
        let model = ImageActionsModel(backend: backend)

        let ok = await model.tag(source: "alpine:latest", target: "BAD REF")

        XCTAssertFalse(ok)
        XCTAssertNotNil(model.notice)
    }

    func testDeleteRemovesAndReloads() async {
        let backend = MockBackend(images: [img("alpine:latest")])
        var reloads = 0
        let model = ImageActionsModel(backend: backend, reloadList: { reloads += 1 })

        await model.delete(reference: "alpine:latest")

        XCTAssertEqual(reloads, 1)
        XCTAssertNil(model.notice)
    }

    func testDeleteOfAlreadyAbsentImageIsBenign() async {
        let backend = MockBackend(images: [])
        backend.failure = BackendError.nonZeroExit(
            command: "container image delete", code: 1, stderr: "Error: image not found")
        var reloads = 0
        let model = ImageActionsModel(backend: backend, reloadList: { reloads += 1 })

        await model.delete(reference: "ghost:1")

        XCTAssertNil(model.notice, "a not-found delete is a benign success")
        XCTAssertEqual(reloads, 1)
    }

    func testDeleteSurfacesDependencyConflictRawStderr() async {
        let backend = MockBackend(images: [img("alpine:latest")])
        backend.failure = BackendError.nonZeroExit(
            command: "container image delete", code: 1,
            stderr: "Error: image is referenced by container \"web\"")
        let model = ImageActionsModel(
            backend: backend, normalize: { ErrorNormalizer.normalize($0) })

        await model.delete(reference: "alpine:latest")

        let notice = try? XCTUnwrap(model.notice)
        XCTAssertTrue(
            notice?.detail.explanation.contains("referenced by container") ?? false,
            "the dependency conflict must be visible verbatim")
    }

    func testDeleteAllContinuesPastFailures() async {
        let backend = MockBackend(images: [img("a:1"), img("b:1", digest: "sha256:b")])
        let model = ImageActionsModel(backend: backend)

        await model.deleteAll(references: ["a:1", "b:1"])

        let remaining = try? await backend.listImages()
        XCTAssertTrue(remaining?.isEmpty ?? false)
    }

    func testComputePruneTargetsReturnsDanglingByDefault() async {
        let backend = MockBackend(images: [
            img("alpine:latest", digest: "sha256:1"),
            img("<none>:<none>", digest: "sha256:2"),
        ])
        let model = ImageActionsModel(backend: backend)

        let targets = await model.computePruneTargets(all: false)

        XCTAssertEqual(targets.map(\.id), ["sha256:2"])
    }

    func testComputePruneTargetsAllReturnsImagesNoContainerReferences() async {
        let backend = MockBackend(
            containers: [
                ContainerSummary(id: "c", name: "web", image: "alpine:latest", state: "running")
            ],
            images: [
                img("alpine:latest", digest: "sha256:1"),
                img("postgres:16", digest: "sha256:2"),
            ])
        let model = ImageActionsModel(backend: backend)

        let targets = await model.computePruneTargets(all: true)

        XCTAssertEqual(
            targets.map(\.reference), ["postgres:16"],
            "only images unreferenced by any container are prune candidates")
    }

    func testPruneReturnsSummaryAndReloads() async {
        let backend = MockBackend(images: [img("<none>:<none>", digest: "sha256:2")])
        var reloads = 0
        let model = ImageActionsModel(backend: backend, reloadList: { reloads += 1 })

        let summary = await model.prune(all: false)

        XCTAssertFalse(summary.message.isEmpty)
        XCTAssertEqual(backend.prunedAll, false)
        XCTAssertEqual(reloads, 1)
    }

    func testPruneFailureSetsNotice() async {
        let backend = MockBackend()
        backend.failure = BackendError.nonZeroExit(
            command: "container image prune", code: 1, stderr: "boom")
        let model = ImageActionsModel(backend: backend)

        _ = await model.prune(all: true)

        XCTAssertNotNil(model.notice)
    }
}
