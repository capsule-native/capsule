//
//  LogWindow.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The detachable log window: a standalone window hosting `LogsPaneView` for the container
//  the model is currently following. The window id is shared by the `Window` scene and the
//  `openWindow` callers (the container Logs… action and the View ▸ Open Log Window command).

import CapsuleDomain
import SwiftUI

public enum LogWindow {
    public static let id = "capsule.logs"
}

/// The content of the detachable log window scene.
public struct LogWindowView: View {
    @Bindable var model: LogsModel

    public init(model: LogsModel) {
        self.model = model
    }

    public var body: some View {
        LogsPaneView(model: model)
            .frame(minWidth: 480, minHeight: 320)
            .navigationTitle(
                model.containerID.map { Text("Logs · \($0)", bundle: .module) }
                    ?? Text("Logs", bundle: .module))
    }
}
