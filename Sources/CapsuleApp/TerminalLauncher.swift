//
//  TerminalLauncher.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Resolves a TerminalPreference to the app the handoff should open the `.command` with, or nil
//  ("use the system default `.command` handler"). Pure + injectable so it is unit-testable;
//  production wires `lookup`/`fileExists` to NSWorkspace/FileManager.

import CapsuleDomain
import Foundation

public func resolveTerminalApp(
    _ preference: TerminalPreference,
    lookup: (String) -> URL?,
    fileExists: (String) -> Bool
) -> URL? {
    switch preference {
    case .systemDefault:
        return nil
    case .terminalApp, .iTerm, .ghostty, .warp:
        guard let identifier = preference.bundleIdentifier else { return nil }
        return lookup(identifier)
    case let .custom(appPath):
        return fileExists(appPath) ? URL(fileURLWithPath: appPath) : nil
    }
}
