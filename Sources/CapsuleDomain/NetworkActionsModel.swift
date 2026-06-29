//
//  NetworkActionsModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Owns the
//  synchronous (non-streaming, near-instant) network operations — create, delete
//  (single/bulk), and prune — mirroring `ImageActionsModel`'s delete/prune. No Activity
//  tasks (decision §9.1). Draft validation (required name + subnet-conflict) lives here, and
//  the Create sheet reads its validity through commandPreview/subnetConflictMessage/canCreate
//  so it never names the backend `NetworkConfiguration` nor calls `NetworkValidation`.

import CapsuleBackend
import Foundation
import Observation

@MainActor
@Observable
public final class NetworkActionsModel {
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

    // MARK: - Validation

    /// Validates a draft into a `NetworkConfiguration`. Fails on an empty name and runs the
    /// subnet-conflict check against the currently-known networks (the model never names a
    /// free subnet — it only reports overlaps). Empty subnet is allowed (CLI auto-assigns).
    public func validatedConfiguration(
        _ draft: NetworkDraft, against existingNetworks: [Network]
    ) -> Result<NetworkConfiguration, CapsuleError> {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return .failure(.invalidInput(field: "name", message: "A network name is required."))
        }
        if let conflict = NetworkValidation.subnetConflict(
            subnet: draft.subnet, against: existingNetworks)
        {
            return .failure(.invalidInput(field: "subnet", message: conflict))
        }
        return .success(configuration(from: draft, name: name))
    }

    /// Builds the backend configuration from a draft, trimming optionals to nil. Shared by
    /// `validatedConfiguration` (post-checks) and `commandPreview` (pre-checks).
    private func configuration(from draft: NetworkDraft, name: String) -> NetworkConfiguration {
        let subnet = draft.subnet.trimmingCharacters(in: .whitespacesAndNewlines)
        let subnetV6 = draft.subnetV6.trimmingCharacters(in: .whitespacesAndNewlines)
        let plugin = draft.plugin.trimmingCharacters(in: .whitespacesAndNewlines)
        return NetworkConfiguration(
            name: name,
            subnet: subnet.isEmpty ? nil : subnet,
            subnetV6: subnetV6.isEmpty ? nil : subnetV6,
            internal: draft.isInternal,
            options: draft.options.compactMap(\.token),
            labels: draft.labels.compactMap(\.token),
            plugin: plugin.isEmpty ? nil : plugin)
    }

    // MARK: - Create-sheet validity accessors

    /// The `container network create …` preview for a draft, tolerant of empty required
    /// fields so the sheet can show it live. Keeps `NetworkConfiguration` out of the UI.
    public func commandPreview(for draft: NetworkDraft) -> String {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = configuration(from: draft, name: name)
        return "container " + config.arguments.joined(separator: " ")
    }

    /// The live subnet-conflict message for the Create sheet (nil = clear). Surfaced here so
    /// the sheet sources its inline warning from the model and never calls NetworkValidation.
    public func subnetConflictMessage(
        for draft: NetworkDraft, against existingNetworks: [Network]
    ) -> String? {
        NetworkValidation.subnetConflict(subnet: draft.subnet, against: existingNetworks)
    }

    /// Whether the draft is valid enough to create: a non-empty name and no subnet conflict.
    /// The sheet ANDs this with its own in-flight flag to gate the Create button.
    public func canCreate(_ draft: NetworkDraft, against existingNetworks: [Network]) -> Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && subnetConflictMessage(for: draft, against: existingNetworks) == nil
    }

    // MARK: - Create

    /// Creates a network from an already-validated configuration. Returns whether it
    /// succeeded, so a sheet can dismiss only on success.
    @discardableResult
    public func create(_ config: NetworkConfiguration) async -> Bool {
        busy.insert(config.name)
        defer { busy.remove(config.name) }
        do {
            try await backend.createNetwork(config)
            await reloadList()
            onActivity("Created network \u{201c}\(config.name)\u{201d}.")
            return true
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
            return false
        }
    }

    /// UI entry point: validate the draft (surfacing any failure as a notice), then create.
    /// The sheet calls this so it never has to name the backend `NetworkConfiguration`.
    @discardableResult
    public func create(draft: NetworkDraft, against existingNetworks: [Network]) async -> Bool {
        switch validatedConfiguration(draft, against: existingNetworks) {
        case let .success(config):
            return await create(config)
        case let .failure(error):
            notice = LifecycleNotice(detail: error.detail)
            return false
        }
    }

    // MARK: - Delete

    /// Deletes one network. Builtin networks never reach here — the UI disables Delete and
    /// the confirmation builder returns nil for them; the CLI itself also refuses, which we
    /// would surface as a notice.
    public func delete(name: String) async {
        busy.insert(name)
        defer { busy.remove(name) }
        do {
            try await backend.deleteNetworks(names: [name])
            await reloadList()
            onActivity("Deleted network \u{201c}\(name)\u{201d}.")
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
        }
    }

    /// Bulk delete (the UI passes only non-builtin names). `network delete` accepts several
    /// names in one call; a batch failure surfaces verbatim as a single notice.
    public func deleteAll(names: [String]) async {
        guard !names.isEmpty else { return }
        names.forEach { busy.insert($0) }
        defer { names.forEach { busy.remove($0) } }
        do {
            try await backend.deleteNetworks(names: names)
            await reloadList()
            onActivity("Deleted \(names.count) network(s).")
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
        }
    }

    // MARK: - Prune

    /// The networks a prune would remove, for the Clean Up sheet's best-effort preview: those
    /// with zero connections, builtins excluded. The runtime owns the authoritative check.
    public func computePruneTargets() async -> [Network] {
        let summaries = (try? await backend.listNetworks()) ?? []
        let containers = ((try? await backend.listContainers(all: true)) ?? [])
            .map(Container.init(summary:))
        let index = AttachmentIndex.build(
            from: containers.map(ContainerAttachmentInfo.init(container:)))
        return
            summaries
            .map {
                Network(summary: $0, connectedContainers: index.containers(forNetwork: $0.name))
            }
            .filter { !$0.isBuiltin && $0.connectedContainers.isEmpty }
    }

    @discardableResult
    public func prune() async -> PruneSummary {
        do {
            let result = try await backend.pruneNetworks()
            await reloadList()
            let message = result.reclaimedDescription ?? "Cleanup complete."
            onActivity(message)
            return PruneSummary(message: message)
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
            return PruneSummary(message: "Cleanup failed.")
        }
    }
}
