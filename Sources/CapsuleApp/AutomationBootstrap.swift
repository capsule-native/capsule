//
//  AutomationBootstrap.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Installs the shared automation service so App Intents (Shortcuts/Siri) and AppleScript can
//  drive the container backend headlessly. Called from the app's @main init: Shortcuts fully
//  launches the app before running an intent, so the service is always present by the time any
//  perform() / NSScriptCommand runs. Lives here (not in the app target) so it is compiled and
//  covered by `swift build`/CI; the backend it wires is the same stateless CLI adapter the UI
//  uses.
//

import CapsuleAutomation
import CapsuleCLIBackend

/// Wires the concrete backend into the automation layer at launch.
public enum AutomationBootstrap {
    /// Installs a live automation service backed by the `container` CLI. Idempotent — a second
    /// call simply replaces the service.
    @MainActor
    public static func install() {
        AutomationRuntime.service = LiveAutomationService(backend: CLIContainerBackend())
        // Retain the AppleScript command classes (referenced only by name from the sdef) so
        // dead-code stripping keeps them registered with the Objective-C runtime.
        AppleScriptSupport.keepCommandClassesAlive()
    }
}
