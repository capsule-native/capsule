//
//  ContainerBackend.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// The port that every container backend must satisfy.
///
/// Concrete adapters (the `container` CLI today; potentially a daemon socket or an
/// in-memory mock tomorrow) conform to this protocol. The domain talks to this
/// abstraction and never to a concrete backend, which keeps the runtime swappable
/// and the higher layers testable.
///
/// Adding a new command is intentionally cheap: declare the method here, implement it
/// in each adapter, and surface it from the domain. No UI changes are required.
public protocol ContainerBackend: Sendable {
    /// Returns version information for the backend client (and server, if any).
    func version() async throws -> BackendVersion

    /// Lists the containers known to the backend.
    func listContainers() async throws -> [ContainerSummary]

    /// Lists the images known to the backend.
    func listImages() async throws -> [ImageSummary]
}
