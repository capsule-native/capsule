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

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in },
        reloadList: @escaping @MainActor () async -> Void = {}
    ) {
        self.backend = backend
        self.normalize = normalize
        self.onActivity = onActivity
        self.reloadList = reloadList
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
