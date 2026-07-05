//
//  CapsuleAppDelegate.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The application delegate — deliberately tiny. It exists for one policy decision that
//  SwiftUI's `App` type cannot express declaratively: what happens when the user closes the
//  last window. Lives in `CapsuleApp` (not the `@main` shim) so it stays testable; the shim
//  only attaches it via `@NSApplicationDelegateAdaptor`.

import AppKit

/// Owns Capsule's "stay resident in the menu bar" lifecycle policy.
///
/// By default a SwiftUI app terminates once its last window closes. Capsule instead keeps
/// running behind its `MenuBarExtra` (see `CapsuleMenuBarContent`) so the container runtime
/// stays reachable; the app quits only on an *explicit* terminate — the menu bar's "Quit
/// Capsule", the standard app-menu ⌘Q, or the language-relaunch flow in
/// `GeneralSettingsView`. None of those go through the last-window-closed heuristic, so they
/// all keep working.
///
/// Reopening after a close is left to SwiftUI's default reopen handling: `openWindow(id:)`
/// from the menu bar re-creates the main window, and a Dock-icon click re-creates it too. If
/// a future macOS ever regresses that, add
/// `applicationShouldHandleReopen(_:hasVisibleWindows:)` returning `true` here.
@MainActor
public final class CapsuleAppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        super.init()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
