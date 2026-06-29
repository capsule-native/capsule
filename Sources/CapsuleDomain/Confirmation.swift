//
//  Confirmation.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. A confirmation is
//  pure data so the UI renders it with one generic sheet and the policy (when a sheet is
//  required) is unit-testable.

import Foundation

/// The kind of destructive operation a confirmation guards.
public enum ConfirmationKind: Sendable, Equatable {
    case kill
    case delete(force: Bool)
    case exportNotStopped
    // Images (Milestone 6)
    case deleteImage
    // Volumes (Milestone 8) — NO force variant (the CLI has no --force).
    case deleteVolume
    case deleteNetwork
    case pruneVolumes
    case pruneNetworks
}

/// A request to confirm a destructive operation, as pure data the UI renders generically.
public struct ConfirmationRequest: Sendable, Equatable, Identifiable {
    public var id: String { "\(kind)-\(targetIDs.joined(separator: ","))" }
    public var title: String
    public var message: String
    public var confirmTitle: String
    public var targetIDs: [String]
    public var kind: ConfirmationKind

    public init(
        title: String, message: String, confirmTitle: String,
        targetIDs: [String], kind: ConfirmationKind
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.targetIDs = targetIDs
        self.kind = kind
    }

    /// Force Stop (kill) needs a confirmation only when more than one container is targeted.
    public static func kill(ids: [String]) -> ConfirmationRequest? {
        guard ids.count > 1 else { return nil }
        return ConfirmationRequest(
            title: "Force Stop \(ids.count) containers?",
            message: "This sends SIGKILL immediately. Unsaved work in these containers is lost.",
            confirmTitle: "Force Stop", targetIDs: ids, kind: .kill)
    }

    /// Delete always confirms; a running target requires force and a Stop-first recommendation.
    public static func delete(ids: [String], anyRunning: Bool) -> ConfirmationRequest? {
        let count = ids.count
        let noun = count == 1 ? "this container" : "\(count) containers"
        let base = "Deleting \(noun) is permanent."
        let message =
            anyRunning
            ? base + " A running container must be stopped first; deleting it now forces removal."
            : base
        return ConfirmationRequest(
            title: count == 1 ? "Delete container?" : "Delete \(count) containers?",
            message: message,
            confirmTitle: anyRunning ? "Force Delete" : "Delete",
            targetIDs: ids, kind: .delete(force: anyRunning))
    }

    /// Exporting a running container risks an inconsistent filesystem — confirm first.
    public static func exportNotStopped(id: String) -> ConfirmationRequest {
        ConfirmationRequest(
            title: "Export a running container?",
            message: "Exporting a running container may capture an inconsistent filesystem. "
                + "Stopping it first is recommended.",
            confirmTitle: "Export Anyway", targetIDs: [id], kind: .exportNotStopped)
    }

    // MARK: Images (Milestone 6)

    /// Deleting an image always confirms; the operation is permanent and may be refused if
    /// the image is still referenced by a container.
    public static func deleteImage(ids: [String]) -> ConfirmationRequest? {
        let count = ids.count
        guard count > 0 else { return nil }
        let noun = count == 1 ? "this image" : "\(count) images"
        return ConfirmationRequest(
            title: count == 1 ? "Delete image?" : "Delete \(count) images?",
            message: "Deleting \(noun) is permanent. An image still referenced by a container "
                + "can't be removed.",
            confirmTitle: "Delete", targetIDs: ids, kind: .deleteImage)
    }

    // MARK: Volumes (Milestone 8)

    /// Deleting a volume always confirms — it permanently destroys data. When the volume is
    /// still mounted, the message names the mounting containers and warns the delete will
    /// fail until they are removed (there is no force-delete).
    public static func deleteVolume(
        names: [String], attachments: AttachmentIndex
    ) -> ConfirmationRequest? {
        guard !names.isEmpty else { return nil }
        let mounters = Array(Set(names.flatMap { attachments.containers(forVolume: $0) })).sorted()
        let subject =
            names.count == 1
            ? "Deleting \(names[0]) permanently destroys its data."
            : "Deleting \(names.count) volumes permanently destroys their data."
        var message = subject
        if !mounters.isEmpty {
            message +=
                " It is mounted by: \(mounters.joined(separator: ", ")); "
                + "delete will fail until they are removed."
        }
        return ConfirmationRequest(
            title: names.count == 1 ? "Delete volume?" : "Delete \(names.count) volumes?",
            message: message,
            confirmTitle: "Delete",
            targetIDs: names, kind: .deleteVolume)
    }

    /// Cleaning up volumes removes every volume with no container references and destroys
    /// their data — always confirm.
    public static func pruneVolumes() -> ConfirmationRequest {
        ConfirmationRequest(
            title: "Clean Up Volumes?",
            message: "This removes all volumes with no container references. Data in those "
                + "volumes is permanently destroyed.",
            confirmTitle: "Clean Up",
            targetIDs: [], kind: .pruneVolumes)
    }

    // MARK: Networks (Milestone 8)

    /// Deleting a network always confirms; a builtin (e.g. `default`) is protected and
    /// returns no request so the UI disables Delete. The message names any connected
    /// containers — there is no `--force`, so delete fails while they remain attached.
    public static func deleteNetwork(
        name: String, isBuiltin: Bool, attachments: AttachmentIndex
    ) -> ConfirmationRequest? {
        guard !isBuiltin else { return nil }
        let connected = attachments.containers(forNetwork: name)
        var message = "Delete network \(name)?"
        if !connected.isEmpty {
            message += " Connected containers: \(connected.joined(separator: ", "))."
        }
        return ConfirmationRequest(
            title: "Delete network?", message: message,
            confirmTitle: "Delete", targetIDs: [name], kind: .deleteNetwork)
    }

    /// Plural variant for bulk-deleting multiple networks. Returns nil for empty. Aggregates
    /// each network's connected containers from the attachment index and names them in the
    /// message. The builtin-protection check lives upstream (the view pre-filters); this
    /// builder assumes every supplied name is deletable.
    public static func deleteNetwork(
        names: [String], attachments: AttachmentIndex
    ) -> ConfirmationRequest? {
        guard !names.isEmpty else { return nil }
        let connected =
            Array(Set(names.flatMap { attachments.containers(forNetwork: $0) })).sorted()
        let subject =
            names.count == 1
            ? "Deleting \(names[0]) permanently removes it."
            : "Permanently removes \(names.count) selected networks."
        var message = subject
        if !connected.isEmpty {
            message +=
                " Connected containers: \(connected.joined(separator: ", "));"
                + " delete will fail until they detach."
        }
        return ConfirmationRequest(
            title: names.count == 1 ? "Delete network?" : "Delete \(names.count) networks?",
            message: message,
            confirmTitle: "Delete",
            targetIDs: names, kind: .deleteNetwork)
    }

    /// Clean Up removes every network with no connections; builtin networks are never
    /// touched. Always confirms (multi-item, data-affecting).
    public static func pruneNetworks() -> ConfirmationRequest {
        ConfirmationRequest(
            title: "Clean Up Networks?",
            message: "This removes every network with no connected containers. "
                + "Builtin networks are never removed.",
            confirmTitle: "Clean Up", targetIDs: [], kind: .pruneNetworks)
    }

}
