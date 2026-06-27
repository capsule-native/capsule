//
//  TaskState.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// The state of a long-running task (a refresh, an action, a build, …).
public enum TaskState: Sendable, Equatable {
    case idle
    case queued
    case running(progress: Double?)
    case succeeded
    case failed(DiagnosticInfo)

    public var isActive: Bool {
        switch self {
        case .queued, .running: return true
        case .idle, .succeeded, .failed: return false
        }
    }
}
