//
//  CLIContainerBackend.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import CapsuleDiagnostics
import Foundation

/// A `ContainerBackend` backed by the `container` CLI, driven through `Process`.
///
/// Milestone 1 wires the type, argument building, and parsing; the actual process
/// invocations are implemented in a later milestone and currently report
/// `BackendError.notImplemented`.
public struct CLIContainerBackend: ContainerBackend {
    /// Location of the backing CLI executable.
    public var executableURL: URL

    private let runner: ProcessRunner

    public init(executableURL: URL = URL(fileURLWithPath: "/usr/local/bin/container")) {
        self.executableURL = executableURL
        self.runner = ProcessRunner()
    }

    public func version() async throws -> BackendVersion {
        Log.backend.debug("CLIContainerBackend.version() requested")
        throw BackendError.notImplemented("version")
    }

    public func listContainers() async throws -> [ContainerSummary] {
        Log.backend.debug("CLIContainerBackend.listContainers() requested")
        throw BackendError.notImplemented("listContainers")
    }

    public func listImages() async throws -> [ImageSummary] {
        Log.backend.debug("CLIContainerBackend.listImages() requested")
        throw BackendError.notImplemented("listImages")
    }
}
