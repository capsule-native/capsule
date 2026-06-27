//
//  WorkspaceModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import Foundation
import Observation

/// The observable state the UI binds to.
///
/// It is `@Observable` (from the `Observation` framework, *not* SwiftUI) so the domain
/// stays UI-free while remaining directly observable by SwiftUI views. It holds a
/// `ContainerBackend` behind its protocol, so it has no knowledge of which adapter is
/// in use.
@MainActor
@Observable
public final class WorkspaceModel {
    public private(set) var containers: [Container] = []
    public private(set) var images: [Image] = []
    public private(set) var loadState: TaskState = .idle

    private let backend: any ContainerBackend

    public init(backend: any ContainerBackend) {
        self.backend = backend
    }

    /// Reloads containers and images from the backend.
    public func refresh() async {
        loadState = .running(progress: nil)
        do {
            containers = try await backend.listContainers().map(Container.init(summary:))
            images = try await backend.listImages().map(Image.init(summary:))
            loadState = .succeeded
        } catch {
            loadState = .failed(
                DiagnosticInfo(
                    summary: "Failed to load resources",
                    underlyingDescription: String(describing: error)
                )
            )
        }
    }
}
