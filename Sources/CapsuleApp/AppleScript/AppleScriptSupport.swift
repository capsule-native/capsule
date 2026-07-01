//
//  AppleScriptSupport.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The AppleScript command classes are referenced only by name (from Capsule.sdef, resolved
//  through the Objective-C runtime), never from Swift code. With DEAD_CODE_STRIPPING enabled the
//  linker could drop them, and the scripting bridge would then report "handler not found". This
//  keep-alive touches every command class at launch so they are retained.
//

import Foundation

enum AppleScriptSupport {
    /// Every scripting command class, referenced so dead-code stripping keeps them registered
    /// with the Objective-C runtime for the sdef's `<cocoa class="…"/>` lookups.
    static let commandClasses: [AnyClass] = [
        CapsuleRunContainerCommand.self,
        CapsulePullImageCommand.self,
        CapsuleBuildImageCommand.self,
        CapsuleCopyFileCommand.self,
        CapsuleExportContainerCommand.self,
        CapsuleStartServicesCommand.self,
        CapsuleStopServicesCommand.self,
        CapsuleReclaimSpaceCommand.self,
        CapsuleListContainersCommand.self,
        CapsuleListImagesCommand.self,
    ]

    /// Forces `commandClasses` to be evaluated so the classes are not stripped.
    static func keepCommandClassesAlive() {
        _ = commandClasses.count
    }
}
