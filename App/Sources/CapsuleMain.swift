//
//  CapsuleMain.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  This is the macOS app target's entry point — intentionally a thin shim. All app
//  logic lives in the `CapsuleApp` SwiftPM module so it stays testable and reusable.

import CapsuleApp
import SwiftUI

@main
struct CapsuleMain: App {
    // Keeps Capsule resident in the menu bar after its last window closes (the app quits only
    // on an explicit terminate). The policy itself lives in `CapsuleAppDelegate`, in the
    // `CapsuleApp` module, so this shim stays logic-free.
    @NSApplicationDelegateAdaptor(CapsuleAppDelegate.self) private var appDelegate

    init() {
        // Install the automation service before any scene renders, so an App Intent or
        // AppleScript command invoked during a headless Shortcuts/Siri launch resolves it.
        AutomationBootstrap.install()
    }

    var body: some Scene {
        CapsuleScene()
    }
}
