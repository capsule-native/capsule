//
//  CapsuleScriptCommands.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The concrete AppleScript verbs. Each maps 1:1 to a <command> in Capsule.sdef via its
//  @objc name and drives the shared AutomationService — the same facade the App Intents use.
//

import CapsuleAutomation
import Foundation

@objc(CapsuleRunContainerCommand)
final class CapsuleRunContainerCommand: CapsuleScriptCommand {
    override func run(service: any AutomationService) async throws -> Any? {
        let image = try requireDirectString("image")
        return try await service.runContainer(image: image, name: optionalArgument("containerName"))
    }
}

@objc(CapsulePullImageCommand)
final class CapsulePullImageCommand: CapsuleScriptCommand {
    override func run(service: any AutomationService) async throws -> Any? {
        let reference = try requireDirectString("image reference")
        return try await service.pullImage(
            reference: reference, platform: optionalArgument("platform"))
    }
}

@objc(CapsuleBuildImageCommand)
final class CapsuleBuildImageCommand: CapsuleScriptCommand {
    override func run(service: any AutomationService) async throws -> Any? {
        let contextPath = try requireDirectString("context path")
        let tag = try requireArgument("tag", name: "tag")
        return try await service.buildImage(
            contextDirectory: URL(fileURLWithPath: contextPath), tag: tag)
    }
}

@objc(CapsuleCopyFileCommand)
final class CapsuleCopyFileCommand: CapsuleScriptCommand {
    override func run(service: any AutomationService) async throws -> Any? {
        let source = try requireDirectString("source path")
        let container = try requireArgument("container", name: "into")
        let containerPath = try requireArgument("containerPath", name: "at")
        try await service.copyToContainer(
            source: URL(fileURLWithPath: source),
            containerID: container,
            containerPath: containerPath)
        return nil
    }
}

@objc(CapsuleExportContainerCommand)
final class CapsuleExportContainerCommand: CapsuleScriptCommand {
    override func run(service: any AutomationService) async throws -> Any? {
        let container = try requireDirectString("container")
        let destination = try requireArgument("destinationPath", name: "to")
        try await service.exportContainer(id: container, to: URL(fileURLWithPath: destination))
        return nil
    }
}

@objc(CapsuleStartServicesCommand)
final class CapsuleStartServicesCommand: CapsuleScriptCommand {
    override func run(service: any AutomationService) async throws -> Any? {
        try await service.startServices()
        return nil
    }
}

@objc(CapsuleStopServicesCommand)
final class CapsuleStopServicesCommand: CapsuleScriptCommand {
    override func run(service: any AutomationService) async throws -> Any? {
        try await service.stopServices()
        return nil
    }
}

@objc(CapsuleReclaimSpaceCommand)
final class CapsuleReclaimSpaceCommand: CapsuleScriptCommand {
    override func run(service: any AutomationService) async throws -> Any? {
        try await service.reclaimSpace()
    }
}

@objc(CapsuleListContainersCommand)
final class CapsuleListContainersCommand: CapsuleScriptCommand {
    override func run(service: any AutomationService) async throws -> Any? {
        let includeStopped = (evaluatedArguments?["includeStopped"] as? Bool) ?? true
        return try await service.listContainers(all: includeStopped)
    }
}

@objc(CapsuleListImagesCommand)
final class CapsuleListImagesCommand: CapsuleScriptCommand {
    override func run(service: any AutomationService) async throws -> Any? {
        try await service.listImages()
    }
}

@objc(CapsuleContainerLogsCommand)
final class CapsuleContainerLogsCommand: CapsuleScriptCommand {
    override func run(service: any AutomationService) async throws -> Any? {
        let container = try requireDirectString("container")
        return try await service.containerLogs(
            id: container, tail: evaluatedArguments?["tail"] as? Int)
    }
}
