//
//  CapsuleCommands.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import SwiftUI

/// Top-level menu commands. Updater and (future) window-management entry points live
/// here so they stay out of the views.
public struct CapsuleCommands: Commands {
    private let updater: any UpdaterController

    public init(updater: any UpdaterController) {
        self.updater = updater
    }

    public var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }
    }
}
