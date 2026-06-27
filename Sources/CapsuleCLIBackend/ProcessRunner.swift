//
//  ProcessRunner.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// A thin async wrapper around `Foundation.Process`.
///
/// This is the *only* place in the codebase that touches `Process`: the domain and UI
/// layers are forbidden from importing it (enforced by the architecture guard). The
/// actual spawn/pipe handling is implemented in a later milestone.
struct ProcessRunner: Sendable {
    struct Result: Sendable, Equatable {
        var stdout: Data
        var stderr: Data
        var exitCode: Int32
    }

    func run(_ executable: URL, arguments: [String]) async throws -> Result {
        _ = (executable, arguments)
        throw CocoaError(.featureUnsupported)
    }
}
