//
//  ImageActionsModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Owns the
//  non-streaming image operations — tag, delete (single/bulk), and prune — mirroring
//  `ContainerLifecycleModel`. Streaming transfers (pull/push/save/load) live in
//  `TaskCenter`; the read surface lives in `ImageBrowserModel`.

import CapsuleBackend
import Foundation
import Observation

@MainActor
@Observable
public final class ImageActionsModel {
    public private(set) var busy: Set<String> = []
    public var notice: LifecycleNotice?
    /// A pending destructive confirmation the UI should present, or nil.
    public var confirmation: ConfirmationRequest?

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void
    private let reloadList: @MainActor () async -> Void
    private let taskCenter: TaskCenter

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in },
        reloadList: @escaping @MainActor () async -> Void = {},
        taskCenter: TaskCenter? = nil
    ) {
        self.backend = backend
        self.normalize = normalize
        self.onActivity = onActivity
        self.reloadList = reloadList
        self.taskCenter = taskCenter ?? TaskCenter(normalize: normalize)
    }

    // MARK: - Tag

    /// Creates a new reference (`target`) for an existing image (`source`). Returns whether
    /// it succeeded, so a sheet can dismiss only on success.
    @discardableResult
    public func tag(source: String, target: String) async -> Bool {
        busy.insert(source)
        defer { busy.remove(source) }
        do {
            try await backend.tagImage(source: source, target: target)
            await reloadList()
            onActivity("Tagged “\(source)” as “\(target)”.")
            return true
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
            return false
        }
    }

    // MARK: - Delete

    public func delete(reference: String) async {
        busy.insert(reference)
        defer { busy.remove(reference) }
        do {
            try await backend.removeImage(reference: reference)
            await reloadList()
            onActivity("Deleted image “\(reference)”.")
        } catch {
            if isBenignAlreadyRemoved(error) {
                await reloadList()
                onActivity("Image “\(reference)” was already removed.")
                return
            }
            notice = LifecycleNotice(detail: normalize(error).detail)
        }
    }

    public func deleteAll(references: [String]) async {
        for reference in references { await delete(reference: reference) }
    }

    // MARK: - Prune

    /// The images a prune would remove, for the Clean Up sheet's preview. By default that is
    /// the dangling (untagged) images; with `all`, every image not referenced by a
    /// container.
    public func computePruneTargets(all: Bool) async -> [Image] {
        let images = ((try? await backend.listImages()) ?? []).map(Image.init(summary:))
        guard all else { return images.filter(\.isDangling) }
        let containers = (try? await backend.listContainers(all: true)) ?? []
        let referenced = Set(containers.map(\.image))
        return images.filter { !referenced.contains($0.reference) }
    }

    @discardableResult
    public func prune(all: Bool) async -> PruneSummary {
        do {
            let result = try await backend.pruneImages(all: all)
            await reloadList()
            let message = result.reclaimedDescription ?? "Cleanup complete."
            onActivity(message)
            return PruneSummary(message: message)
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
            return PruneSummary(message: "Cleanup failed.")
        }
    }

    // MARK: - Transfers (registered as Activity tasks)

    /// Pulls an image, streaming progress into a task; refreshes the list on success.
    @discardableResult
    public func pull(reference: String, platform: String?) -> OperationTask {
        onActivity("Pulling “\(reference)”…")
        return taskCenter.runStreaming(
            kind: .pull, title: "Pull \(reference)",
            onSuccess: { [reloadList] in await reloadList() }
        ) { [backend] in
            backend.pullImage(reference: reference, platform: platform)
        }
    }

    /// Pushes an image to its registry, streaming progress into a task.
    @discardableResult
    public func push(reference: String, platform: String?) -> OperationTask {
        onActivity("Pushing “\(reference)”…")
        return taskCenter.runStreaming(kind: .push, title: "Push \(reference)") { [backend] in
            backend.pushImage(reference: reference, platform: platform)
        }
    }

    /// Saves one or more images to a tar archive as a task.
    @discardableResult
    public func save(references: [String], to url: URL, platform: String?) -> OperationTask {
        taskCenter.runAsync(
            kind: .save, title: "Save \(references.joined(separator: ", "))"
        ) { [backend] in
            try await backend.saveImage(references: references, to: url, platform: platform)
        }
    }

    /// Loads images from a tar archive as a task; refreshes the list on success.
    @discardableResult
    public func load(from url: URL) -> OperationTask {
        taskCenter.runAsync(
            kind: .load, title: "Load \(url.lastPathComponent)",
            onSuccess: { [reloadList] in await reloadList() }
        ) { [backend] in
            try await backend.loadImage(from: url)
        }
    }

    /// Re-runs a finished transfer task (the sheets/Activity pane Retry affordance).
    public func retryTask(_ task: OperationTask) {
        taskCenter.retry(task)
    }

    // MARK: - Helpers

    /// Delete is idempotent: a `notFound` means the image is already gone — a benign
    /// success. Daemon outages are never benign.
    private func isBenignAlreadyRemoved(_ error: any Error) -> Bool {
        guard case let BackendError.nonZeroExit(_, _, stderr) = error else { return false }
        let s = stderr.lowercased()
        let gone = s.contains("notfound") || s.contains("not found")
        let daemon =
            s.contains("xpc") || s.contains("launchd") || s.contains("connection refused")
        return gone && !daemon
    }
}
