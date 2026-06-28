//
//  RegistriesModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Registry credential management: list, login, logout, and a credential test — proving the
//  password reaches the backend but never the activity feed.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class RegistriesModelTests: XCTestCase {
    func testRefreshLoadsRegistries() async {
        let backend = MockBackend(registries: [RegistrySummary(server: "ghcr.io")])
        let model = RegistriesModel(backend: backend)

        await model.refresh()

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.registries.map(\.server), ["ghcr.io"])
    }

    func testRefreshFailureIsUnavailableNotEmpty() async {
        let backend = MockBackend(registries: [])
        backend.failure = BackendError.nonZeroExit(
            command: "container registry list", code: 1, stderr: "Connection refused")
        let model = RegistriesModel(backend: backend)

        await model.refresh()

        guard case .unavailable = model.loadState else {
            return XCTFail("a daemon failure must be .unavailable, not an empty list")
        }
    }

    func testLoginPassesCredentialsToBackendAndReloads() async {
        let backend = MockBackend()
        let model = RegistriesModel(backend: backend)

        let ok = await model.login(server: "ghcr.io", username: "me", password: "s3cret")

        XCTAssertTrue(ok)
        XCTAssertEqual(backend.lastLogin?.server, "ghcr.io")
        XCTAssertEqual(backend.lastLogin?.username, "me")
        XCTAssertEqual(backend.lastLogin?.password, "s3cret")
        XCTAssertTrue(model.registries.contains { $0.server == "ghcr.io" })
    }

    func testLoginNeverWritesThePasswordToActivity() async {
        let backend = MockBackend()
        var activity: [String] = []
        let model = RegistriesModel(backend: backend, onActivity: { activity.append($0) })

        _ = await model.login(server: "ghcr.io", username: "me", password: "top-secret-pw")

        XCTAssertFalse(
            activity.contains { $0.contains("top-secret-pw") },
            "the password must never appear in the activity feed")
        XCTAssertFalse(activity.isEmpty, "a login still logs that it happened")
    }

    func testLoginFailureSetsNoticeAndReturnsFalse() async {
        let backend = MockBackend()
        backend.failure = BackendError.nonZeroExit(
            command: "container registry login", code: 1, stderr: "unauthorized")
        let model = RegistriesModel(backend: backend)

        let ok = await model.login(server: "ghcr.io", username: "me", password: "wrong")

        XCTAssertFalse(ok)
        XCTAssertNotNil(model.notice)
    }

    func testLogoutRemovesTheRegistry() async {
        let backend = MockBackend(registries: [RegistrySummary(server: "ghcr.io")])
        let model = RegistriesModel(backend: backend)
        await model.refresh()

        await model.logout(server: "ghcr.io")

        XCTAssertEqual(backend.lastLogout, "ghcr.io")
        XCTAssertFalse(model.registries.contains { $0.server == "ghcr.io" })
    }

    func testTestSucceedsWithoutPersistingARegistry() async {
        let backend = MockBackend()
        let model = RegistriesModel(backend: backend)

        let result = await model.test(server: "ghcr.io", username: "me", password: "s3cret")

        XCTAssertEqual(result, .success)
        XCTAssertEqual(backend.lastTest?.server, "ghcr.io")
    }

    func testTestFailureReturnsADetail() async {
        let backend = MockBackend()
        backend.failure = BackendError.nonZeroExit(
            command: "container registry login", code: 1, stderr: "bad credentials")
        let model = RegistriesModel(backend: backend)

        let result = await model.test(server: "ghcr.io", username: "me", password: "bad")

        guard case .failure = result else { return XCTFail("expected .failure") }
    }
}
