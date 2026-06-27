//
//  CapsuleScene.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import CapsuleUI
import SwiftUI

/// The application's root `Scene`.
///
/// The Xcode app target's tiny `@main` shim renders this; all real lifecycle, command,
/// and composition logic lives in this module so it stays testable and out of the
/// app-bundle target.
@MainActor
public struct CapsuleScene: Scene {
    @State private var model: WorkspaceModel
    private let updater: any UpdaterController

    public init() {
        self.init(environment: .live())
    }

    public init(environment: AppEnvironment) {
        self._model = State(initialValue: environment.workspaceModel)
        self.updater = environment.updater
    }

    public var body: some Scene {
        WindowGroup(id: WindowManagement.mainWindowID) {
            RootView(model: model)
        }
        .commands {
            CapsuleCommands(updater: updater)
        }
    }
}
