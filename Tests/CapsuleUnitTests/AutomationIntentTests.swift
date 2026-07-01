//
//  AutomationIntentTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Validates that App Intents resolve the installed AutomationRuntime service and drive the
//  backend port. Installing a LiveAutomationService over a MockBackend and calling perform()
//  exercises the exact runtime path Shortcuts/Siri use, without an app bundle.
//

import CapsuleAutomation
import CapsuleBackend
import XCTest

final class AutomationIntentTests: XCTestCase {
    /// Installs a fresh service (over `backend`) for the intent under test to resolve, and
    /// returns the backend so the test can assert on the captured call.
    @discardableResult
    private func install(_ backend: MockBackend) -> MockBackend {
        AutomationRuntime.service = LiveAutomationService(backend: backend)
        return backend
    }

    override func tearDown() {
        AutomationRuntime.service = nil
        super.tearDown()
    }

    func testStartServicesIntentStartsSystem() async throws {
        let backend = install(MockBackend(systemRunState: .stopped))
        _ = try await StartServicesIntent().perform()
        let status = try await backend.systemStatus()
        XCTAssertEqual(status, .running)
    }

    func testStopServicesIntentStopsSystem() async throws {
        let backend = install(MockBackend(systemRunState: .running))
        _ = try await StopServicesIntent().perform()
        let status = try await backend.systemStatus()
        XCTAssertEqual(status, .stopped)
    }

    func testRunContainerIntentRunsDetachedWithImageAndName() async throws {
        let backend = install(MockBackend())
        _ = try await RunContainerIntent(image: "nginx:latest", name: "web").perform()
        XCTAssertEqual(backend.lastRunConfig?.image, "nginx:latest")
        XCTAssertEqual(backend.lastRunConfig?.name, "web")
        XCTAssertTrue(backend.lastRunConfig?.detach ?? false, "automation runs are always detached")
    }

    func testCopyToContainerIntentReachesBackend() async throws {
        let backend = install(MockBackend())
        _ = try await CopyToContainerIntent(
            sourcePath: "/tmp/f.txt", container: "web", containerPath: "/app/f.txt"
        ).perform()
        XCTAssertEqual(backend.lastCopy?.hostURL, URL(fileURLWithPath: "/tmp/f.txt"))
        XCTAssertEqual(backend.lastCopy?.containerID, "web")
        XCTAssertEqual(backend.lastCopy?.containerPath, "/app/f.txt")
    }

    func testExportContainerIntentWritesToDestination() async throws {
        let backend = install(MockBackend())
        _ = try await ExportContainerIntent(
            container: "web", destinationPath: "/tmp/web.tar"
        ).perform()
        XCTAssertEqual(backend.lastExportURL, URL(fileURLWithPath: "/tmp/web.tar"))
    }

    func testBuildImageIntentCapturesContextAndTag() async throws {
        let backend = install(MockBackend())
        _ = try await BuildImageIntent(contextPath: "/ctx", tag: "app:1").perform()
        XCTAssertEqual(backend.lastBuildConfig?.tag, "app:1")
        XCTAssertEqual(backend.lastBuildConfig?.contextDirectory, URL(fileURLWithPath: "/ctx"))
    }

    /// The value-returning intents (pull/logs/reclaim/list) resolve their service and run to
    /// completion; their returned values are asserted at the service layer in
    /// AutomationServiceTests.
    func testValueReturningIntentsPerformWithoutThrowing() async throws {
        install(MockBackend())
        _ = try await PullImageIntent(reference: "nginx:latest").perform()
        _ = try await ContainerLogsIntent(container: "web").perform()
        _ = try await ReclaimSpaceIntent().perform()
        _ = try await ListContainersIntent(includeStopped: true).perform()
        _ = try await ListImagesIntent().perform()
    }

    func testIntentThrowsWhenServiceNotInstalled() async throws {
        AutomationRuntime.service = nil
        do {
            _ = try await StartServicesIntent().perform()
            XCTFail("expected AutomationError.notReady")
        } catch let error as AutomationError {
            XCTAssertEqual(error, .notReady)
        }
    }
}
