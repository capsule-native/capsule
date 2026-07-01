//
//  AutomationRuntime.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The seam every automation surface resolves its service through. The app sets `service`
//  once at launch (before any App Intent or AppleScript command can run — Shortcuts fully
//  launches the app first); tests set it directly. This is deliberately a small, thread-safe
//  registry rather than App Intents' `@Dependency`: `@Dependency` is injected only by the
//  App Intents runtime during its perform flow, so an intent's `perform()` is not unit-testable
//  through it. A registry keeps `perform()` fully testable and works identically in production.
//

import Foundation

/// Process-wide holder for the shared ``AutomationService``.
public enum AutomationRuntime {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _service: (any AutomationService)?

    /// The registered service (nil until the app — or a test — installs one).
    public static var service: (any AutomationService)? {
        get { lock.withLock { _service } }
        set { lock.withLock { _service = newValue } }
    }

    /// The registered service, or a thrown ``AutomationError/notReady`` explaining that the
    /// app has not finished launching / installing it.
    public static func requireService() throws -> any AutomationService {
        guard let service = service else { throw AutomationError.notReady }
        return service
    }
}

/// Errors surfaced to Shortcuts / AppleScript callers.
public enum AutomationError: Error, LocalizedError, Equatable {
    /// No service is installed yet (the app has not finished launching).
    case notReady

    public var errorDescription: String? {
        switch self {
        case .notReady:
            return String(
                localized: "Capsule's automation service is not available yet.",
                bundle: .module)
        }
    }
}
