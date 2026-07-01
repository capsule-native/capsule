//
//  RegistriesModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Registry credential
//  management for the Registries preferences pane: list, login, logout, and a credential
//  test. The password flows straight through to the backend (delivered via stdin there) and
//  is never retained or logged — only the fact that a login happened is recorded.

import CapsuleBackend
import Foundation
import Observation

/// The domain's view of a registry login (apple/container exposes only the server locally).
public struct Registry: Sendable, Equatable, Identifiable {
    public var server: String
    public var id: String { server }

    public init(server: String) { self.server = server }
}

/// The load state of the registry list, distinguishing a down service from no logins.
public enum RegistryLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case unavailable(ErrorDetail)
}

/// The outcome of a credential test.
public enum RegistryTestResult: Sendable, Equatable {
    case success
    case failure(ErrorDetail)
}

@MainActor
@Observable
public final class RegistriesModel {
    public private(set) var registries: [Registry] = []
    public private(set) var loadState: RegistryLoadState = .idle
    public var notice: LifecycleNotice?

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.backend = backend
        self.normalize = normalize
        self.onActivity = onActivity
    }

    public func refresh() async {
        loadState = .loading
        do {
            let summaries = try await backend.listRegistries()
            registries = summaries.map { Registry(server: $0.server) }
            loadState = .loaded
        } catch {
            registries = []
            loadState = .unavailable(normalize(error).detail)
        }
    }

    /// Logs in to a registry. Returns whether it succeeded. The password is forwarded to the
    /// backend and then discarded; it is never stored or written to the activity feed.
    @discardableResult
    public func login(server: String, username: String?, password: String?) async -> Bool {
        do {
            try await backend.registryLogin(server: server, username: username, password: password)
            await refresh()
            onActivity("Logged in to \(server).")
            return true
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
            return false
        }
    }

    /// The faithful `registry login` argv — it carries `--password-stdin` and the optional
    /// username but never the secret (delivered via stdin), so this is safe to show verbatim.
    public func loginInvocation(server: String, username: String?) -> CommandInvocation {
        CommandInvocation(CLICommand.registryLogin(server: server, username: username))
    }

    public func logout(server: String) async {
        do {
            try await backend.registryLogout(server: server)
            await refresh()
            onActivity("Logged out of \(server).")
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
        }
    }

    /// Validates credentials against a registry (apple/container has no dry-run, so this is a
    /// real login). The password is never retained or logged.
    public func test(
        server: String, username: String?, password: String?
    ) async
        -> RegistryTestResult
    {
        do {
            try await backend.registryTest(server: server, username: username, password: password)
            return .success
        } catch {
            return .failure(normalize(error).detail)
        }
    }
}
