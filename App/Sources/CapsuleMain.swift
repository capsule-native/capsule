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
    var body: some Scene {
        CapsuleScene()
    }
}
