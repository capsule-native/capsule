//
//  TerminalPreference.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Which terminal app
//  Capsule opens for the "Open in Terminal" + DNS sudo handoffs. Pure value type; the App layer
//  resolves it to an installed app, the UI edits it via @AppStorage(TerminalPreference.storageKey).

public enum TerminalPreference: Sendable, Equatable, Hashable {
    case systemDefault
    case terminalApp
    case iTerm
    case ghostty
    case warp
    case custom(appPath: String)

    /// The single UserDefaults key shared by the settings UI and the handoff read.
    public static let storageKey = "capsule.terminalPreference"

    /// The app's bundle identifier, or nil for `systemDefault` (no specific app) and `custom`
    /// (identified by a path, not an id).
    public var bundleIdentifier: String? {
        switch self {
        case .terminalApp: return "com.apple.Terminal"
        case .iTerm: return "com.googlecode.iterm2"
        case .ghostty: return "com.mitchellh.ghostty"
        case .warp: return "dev.warp.Warp-Stable"
        case .systemDefault, .custom: return nil
        }
    }

    public var customAppPath: String? {
        if case let .custom(path) = self { return path }
        return nil
    }

    /// Stable string for UserDefaults.
    public var storageValue: String {
        switch self {
        case .systemDefault: return "systemDefault"
        case .terminalApp: return "com.apple.Terminal"
        case .iTerm: return "com.googlecode.iterm2"
        case .ghostty: return "com.mitchellh.ghostty"
        case .warp: return "dev.warp.Warp-Stable"
        case let .custom(path): return "custom:\(path)"
        }
    }

    public init?(storage: String) {
        switch storage {
        case "systemDefault": self = .systemDefault
        case "com.apple.Terminal": self = .terminalApp
        case "com.googlecode.iterm2": self = .iTerm
        case "com.mitchellh.ghostty": self = .ghostty
        case "dev.warp.Warp-Stable": self = .warp
        default:
            let prefix = "custom:"
            guard storage.hasPrefix(prefix) else { return nil }
            self = .custom(appPath: String(storage.dropFirst(prefix.count)))
        }
    }
}
