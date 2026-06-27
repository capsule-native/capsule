//
//  Action.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// An action a user can invoke against a resource.
///
/// Adding a new command means adding a case here and implementing it in a backend
/// adapter — no view code needs to change. See `CONTRIBUTING.md`.
public enum ResourceAction: Sendable, Equatable {
    case start(containerID: String)
    case stop(containerID: String)
    case restart(containerID: String)
    case remove(containerID: String)
    case inspect(containerID: String)

    /// A stable identifier suitable for logging, automation, and telemetry.
    public var verb: String {
        switch self {
        case .start: return "start"
        case .stop: return "stop"
        case .restart: return "restart"
        case .remove: return "remove"
        case .inspect: return "inspect"
        }
    }
}
