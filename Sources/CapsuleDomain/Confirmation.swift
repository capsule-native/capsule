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

}
