//
//  Pasteboard.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  A tiny wrapper over `NSPasteboard` for the copy actions in the image surface. AppKit is
//  permitted in the UI layer (the arch guard only forbids backend imports there).

import AppKit

enum Pasteboard {
    /// Replaces the general pasteboard's contents with `string`.
    static func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
