//
//  AppEnvironment.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import CapsuleCLIBackend
import CapsuleDomain
import Foundation

/// The composition root.
///
/// This is the single place that knows about concrete adapters and wires them into the
/// domain. The UI and domain layers stay ignorant of which backend is in use, which is
/// what keeps the architecture testable and swappable.
@MainActor
public struct AppEnvironment {
    public var workspaceModel: WorkspaceModel
    public var updater: any UpdaterController

    public init(workspaceModel: WorkspaceModel, updater: any UpdaterController) {
        self.workspaceModel = workspaceModel
        self.updater = updater
    }

    /// The production environment: CLI backend + (placeholder) updater.
    public static func live() -> AppEnvironment {
        let backend: any ContainerBackend = CLIContainerBackend()
        return AppEnvironment(
            workspaceModel: WorkspaceModel(backend: backend),
            updater: NoopUpdaterController()
        )
    }
}
