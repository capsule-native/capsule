//
//  VolumeActionsModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Owns the
//  non-streaming volume operations — create, delete (single/bulk), and prune — mirroring
//  `ImageActionsModel`. These are near-instant, so they use a `busy` set and a
//  `LifecycleNotice` on failure rather than Activity tasks. It also exposes Domain-primitive
//  accessors (commandPreview / validationMessage / isValid / create(draft:)) so the create
//  sheet can stay free of any backend `*Configuration` type — mirroring how RunModel/BuildModel
//  back QuickRunSheet/BuildSheet. The read surface lives in `VolumeBrowserModel`.

import CapsuleBackend
import Foundation
import Observation

@MainActor
@Observable
public final class VolumeActionsModel {
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

    // MARK: - Create

    /// Creates a volume from a configuration. Returns whether it succeeded so a sheet can
    /// dismiss only on success.
    @discardableResult
    public func create(_ config: VolumeConfiguration) async -> Bool {
        busy.insert(config.name)
        defer { busy.remove(config.name) }
        do {
            try await backend.createVolume(config)
            await reloadList()
            onActivity("Created volume “\(config.name)”.")
            return true
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
            return false
        }
    }

    /// Validates a draft, then creates. A validation failure sets `notice` and returns false
    /// without touching the backend; on success it routes through `create(_ config:)`. This is
    /// the entry point the create sheet calls, keeping the UI free of `VolumeConfiguration`.
    @discardableResult
    public func create(draft: VolumeDraft) async -> Bool {
        switch validatedConfiguration(draft) {
        case let .success(config):
            return await create(config)
        case let .failure(error):
            notice = LifecycleNotice(detail: error.detail)
            return false
        }
    }

    // MARK: - Delete

    public func delete(name: String) async {
        await deleteAll(names: [name])
    }

    /// Deletes one or more volumes in a single `volume delete` call (there is no `--force`;
    /// the runtime refuses an in-use volume and we surface that error).
    public func deleteAll(names: [String]) async {
        guard !names.isEmpty else { return }
        names.forEach { busy.insert($0) }
        defer { names.forEach { busy.remove($0) } }
        do {
            try await backend.deleteVolumes(names: names)
            await reloadList()
            onActivity(
                names.count == 1
                    ? "Deleted volume “\(names[0])”." : "Deleted \(names.count) volumes.")
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
        }
    }

    // MARK: - Prune

    /// The volumes a prune would remove: those with zero attachments (best-effort, computed
    /// from the attachment index). The runtime owns the authoritative reference check.
    public func computePruneTargets() async -> [Volume] {
        let summaries = (try? await backend.listVolumes()) ?? []
        let containers = (try? await backend.listContainers(all: true)) ?? []
        let index = AttachmentIndex.build(
            from: containers.map(Container.init(summary:)).map(
                ContainerAttachmentInfo.init(container:)))
        return
            summaries
            .map { Volume(summary: $0, attachedContainers: index.containers(forVolume: $0.name)) }
            .filter { $0.attachedContainers.isEmpty }
    }

    @discardableResult
    public func prune() async -> PruneSummary {
        do {
            let result = try await backend.pruneVolumes()
            await reloadList()
            let message = result.reclaimedDescription ?? "Cleanup complete."
            onActivity(message)
            return PruneSummary(message: message)
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
            return PruneSummary(message: "Cleanup failed.")
        }
    }

    // MARK: - Validation

    /// Validates a draft into a `VolumeConfiguration`, or returns the first field error.
    public func validatedConfiguration(
        _ draft: VolumeDraft
    ) -> Result<VolumeConfiguration, CapsuleError> {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return .failure(.invalidInput(field: "name", message: "Enter a volume name."))
        }
        let size = draft.size.trimmingCharacters(in: .whitespacesAndNewlines)
        if !size.isEmpty, !VolumeDraft.isValidSize(size) {
            return .failure(
                .invalidInput(
                    field: "size",
                    message: "Size must be a number with a K/M/G/T/P suffix, e.g. 10G."))
        }
        return .success(configuration(from: draft, name: name))
    }

    // MARK: - Domain-primitive accessors (consumed by CreateVolumeSheet)

    /// The `container …` command the current draft would run. Renders live: entered fields
    /// (size, labels, options) appear even when the name is not yet entered. Returns a plain
    /// String so the sheet never names `VolumeConfiguration` or touches `.arguments`.
    /// The faithful `container volume create …` invocation. When the name is empty the
    /// trailing positional would be an empty token — drop it so the preview stays clean.
    public func commandInvocation(for draft: VolumeDraft) -> CommandInvocation {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var argv = configuration(from: draft, name: name).arguments
        if name.isEmpty, !argv.isEmpty { argv.removeLast() }
        return CommandInvocation(argv)
    }

    /// The redacted preview string, derived from `commandInvocation(for:)`.
    public func commandPreview(for draft: VolumeDraft) -> String {
        commandInvocation(for: draft).displayString
    }

    /// The `container volume prune` invocation, for the Clean Up sheet's preview.
    public var pruneInvocation: CommandInvocation { CommandInvocation(CLICommand.pruneVolumes()) }

    // MARK: - Private helpers

    /// Builds a `VolumeConfiguration` from a draft tolerantly: name may be empty and an
    /// invalid size string is silently dropped to nil. Shared by `validatedConfiguration`
    /// (post-strict-checks) and `commandPreview` (pre-checks, for live UI rendering).
    private func configuration(from draft: VolumeDraft, name: String) -> VolumeConfiguration {
        let size = draft.size.trimmingCharacters(in: .whitespacesAndNewlines)
        return VolumeConfiguration(
            name: name,
            size: size.isEmpty || !VolumeDraft.isValidSize(size) ? nil : size,
            options: draft.options.compactMap(\.token),
            labels: draft.labels.compactMap(\.token))
    }

    /// nil when the draft is valid; otherwise the human-readable reason (for inline display).
    public func validationMessage(_ draft: VolumeDraft) -> String? {
        switch validatedConfiguration(draft) {
        case .success:
            return nil
        case let .failure(error):
            return error.detail.explanation
        }
    }

    /// Whether the draft validates — drives the Create button's enabled state.
    public func isValid(_ draft: VolumeDraft) -> Bool {
        if case .success = validatedConfiguration(draft) { return true }
        return false
    }
}
