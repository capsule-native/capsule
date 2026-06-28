//
//  Log.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation
import os

/// The OSLog categories Capsule logs under, one per subsystem of the app.
public enum LogCategory: String, Sendable, CaseIterable {
    case app
    case backend
    case ui
    case tasks
    case automation
}

/// Centralized `OSLog`/`Logger` wrappers so every module logs under a consistent
/// subsystem and category set. Group recent entries by `LogCategory` when assembling a
/// diagnostic bundle.
public enum Log {
    public static let subsystem = "com.capsule.app"

    /// A `Logger` bound to `subsystem` for the given category.
    public static func logger(for category: LogCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    public static let app = logger(for: .app)
    public static let backend = logger(for: .backend)
    public static let ui = logger(for: .ui)
    public static let tasks = logger(for: .tasks)
    public static let automation = logger(for: .automation)
}
