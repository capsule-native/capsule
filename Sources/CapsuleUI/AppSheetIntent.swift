//
//  AppSheetIntent.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain

/// A request to present one of the app-level sheets from a non-list surface (the command
/// palette or the menu bar). The list views keep their own local sheet enums; this is the
/// shared entry point routed through `ShellState.pendingSheet` and presented by
/// `AppShellView` against the existing sheet views/models.
public enum AppSheetIntent: Identifiable {
    case run(imageReference: String?)
    case build
    case pull
    case copy(containerID: String?)
    case export(containerID: String)
    case console(seed: CommandInvocation?)

    public var id: String {
        switch self {
        case let .run(imageReference): return "run-\(imageReference ?? "")"
        case .build: return "build"
        case .pull: return "pull"
        case let .copy(containerID): return "copy-\(containerID ?? "")"
        case let .export(containerID): return "export-\(containerID)"
        case .console: return "console"
        }
    }
}
