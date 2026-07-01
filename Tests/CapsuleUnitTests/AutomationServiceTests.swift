//
//  AutomationServiceTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Exercises LiveAutomationService's mapping onto the ContainerBackend port with a MockBackend,
//  covering the value-returning operations App Intents/AppleScript expose.
//

import CapsuleAutomation
import CapsuleBackend
import Foundation
import XCTest

final class AutomationServiceTests: XCTestCase {
    func testListContainersMapsNamesAndHonorsAllFlag() async throws {
        let service = LiveAutomationService(backend: MockBackend())
        let all = try await service.listContainers(all: true)
        XCTAssertEqual(all, ["web", "db", "cache"])
        let running = try await service.listContainers(all: false)
        XCTAssertEqual(running, ["web", "cache"])
    }

    func testListImagesReturnsReferences() async throws {
        let service = LiveAutomationService(backend: MockBackend())
        let refs = try await service.listImages()
        XCTAssertEqual(refs, ["docker.io/library/alpine:latest", "docker.io/library/postgres:16"])
    }

    func testContainerLogsJoinsLines() async throws {
        let service = LiveAutomationService(backend: MockBackend())
        let logs = try await service.containerLogs(id: "web", tail: nil)
        XCTAssertEqual(logs, "starting\nready")
    }

    func testPullImageReturnsTranscript() async throws {
        let service = LiveAutomationService(backend: MockBackend())
        let transcript = try await service.pullImage(reference: "nginx:latest", platform: nil)
        XCTAssertEqual(transcript, "starting\nready")
    }

    func testBuildImageCapturesConfigAndReturnsTranscript() async throws {
        let backend = MockBackend()
        let service = LiveAutomationService(backend: backend)
        let transcript = try await service.buildImage(
            contextDirectory: URL(fileURLWithPath: "/ctx"), tag: "app:1")
        XCTAssertEqual(transcript, "starting\nready")
        XCTAssertEqual(backend.lastBuildConfig?.tag, "app:1")
        XCTAssertEqual(backend.lastBuildConfig?.contextDirectory, URL(fileURLWithPath: "/ctx"))
    }

    func testReclaimSpaceSummarizesAllThreeResourceKinds() async throws {
        let service = LiveAutomationService(backend: MockBackend())
        let summary = try await service.reclaimSpace()
        XCTAssertTrue(summary.contains("Containers:"))
        XCTAssertTrue(summary.contains("Images:"))
        XCTAssertTrue(summary.contains("Volumes:"))
    }

    func testRunContainerIsAlwaysDetachedAndCapturesConfig() async throws {
        let backend = MockBackend()
        let service = LiveAutomationService(backend: backend)
        let id = try await service.runContainer(image: "nginx", name: "n")
        XCTAssertFalse(id.isEmpty)
        XCTAssertEqual(backend.lastRunConfig?.image, "nginx")
        XCTAssertEqual(backend.lastRunConfig?.name, "n")
        XCTAssertTrue(backend.lastRunConfig?.detach ?? false)
    }

    func testExportAndCopyReachBackend() async throws {
        let backend = MockBackend()
        let service = LiveAutomationService(backend: backend)
        try await service.exportContainer(id: "web", to: URL(fileURLWithPath: "/tmp/x.tar"))
        XCTAssertEqual(backend.lastExportURL, URL(fileURLWithPath: "/tmp/x.tar"))
        try await service.copyToContainer(
            source: URL(fileURLWithPath: "/tmp/f"), containerID: "web", containerPath: "/app/f")
        XCTAssertEqual(backend.lastCopy?.hostURL, URL(fileURLWithPath: "/tmp/f"))
        XCTAssertEqual(backend.lastCopy?.containerID, "web")
        XCTAssertEqual(backend.lastCopy?.containerPath, "/app/f")
    }

    func testStartStopToggleSystemState() async throws {
        let backend = MockBackend(systemRunState: .stopped)
        let service = LiveAutomationService(backend: backend)
        try await service.startServices()
        var status = try await backend.systemStatus()
        XCTAssertEqual(status, .running)
        try await service.stopServices()
        status = try await backend.systemStatus()
        XCTAssertEqual(status, .stopped)
    }
}
