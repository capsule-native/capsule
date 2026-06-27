//
//  Log.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation
import os

/// Centralized `OSLog`/`Logger` wrappers so every module logs under a consistent
/// subsystem and category set.
public enum Log {
    public static let subsystem = "com.capsule.app"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let backend = Logger(subsystem: subsystem, category: "backend")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
    public static let automation = Logger(subsystem: subsystem, category: "automation")
}
