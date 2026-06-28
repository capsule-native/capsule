//
//  SystemStatusParser.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  `container system status` prints a short human line rather than JSON, and may exit
//  non-zero when the service is simply stopped. This parser reads both streams leniently
//  so a *reachable* "not running" maps to `.stopped`; an *unreachable* service (a spawn
//  or XPC failure) never reaches here — the backend throws before parsing.

import CapsuleBackend
import Foundation

public enum SystemStatusParser {
    /// Interprets the combined stdout/stderr of `container system status`.
    ///
    /// Returns ``SystemRunState/running`` only when the text affirmatively says the
    /// service is running (and not "not running"); every other reachable response —
    /// "not running", "stopped", or empty — is ``SystemRunState/stopped``.
    public static func parse(stdout: String, stderr: String) -> SystemRunState {
        let text = (stdout + "\n" + stderr).lowercased()
        if text.contains("not running") || text.contains("stopped") || text.contains("not started")
        {
            return .stopped
        }
        return text.contains("running") ? .running : .stopped
    }
}
