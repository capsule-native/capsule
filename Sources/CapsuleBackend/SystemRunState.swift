//
//  SystemRunState.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// Whether the container system service (the apiserver / daemon) is currently up.
///
/// This is intentionally a two-state value: a richer health story (versions,
/// capabilities, errors) is assembled in the domain from this plus ``BackendVersion``.
/// A backend that cannot even reach the service to answer the question throws instead of
/// returning a value, so "stopped" always means a clean, reachable "not running".
public enum SystemRunState: String, Sendable, Equatable, Codable {
    case running
    case stopped
}
