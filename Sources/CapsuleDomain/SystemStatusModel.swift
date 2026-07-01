//
//  SystemStatusModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The model is
//  `@Observable` (from `Observation`, not SwiftUI) so the UI can bind to it while the
//  domain stays UI-free.

import CapsuleBackend
import Foundation
import Observation

/// Owns the system-health story the shell binds to: probes `systemStatus` + `version`,
/// derives capabilities into UI-facing features, and drives Start/Stop Services.
///
/// Error normalization lives in `CapsuleDiagnostics`, which the domain cannot import, so
/// the concrete `Error → CapsuleError` mapping is injected by the composition root. The
/// default is a minimal passthrough so previews/tests work without wiring.
@MainActor
@Observable
public final class SystemStatusModel {
    public private(set) var health: SystemHealth = .unknown
    public private(set) var compatibilityWarning: String?

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void
    private let taskCenter: TaskCenter?

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in },
        taskCenter: TaskCenter? = nil
    ) {
        self.backend = backend
        self.normalize = normalize
        self.onActivity = onActivity
        self.taskCenter = taskCenter
    }

    /// The fallback normalizer used when the composition root injects none: pass through
    /// an existing `CapsuleError`, otherwise wrap as `.unknown`.
    public nonisolated static let defaultNormalize: @Sendable (any Error) -> CapsuleError = {
        error in
        (error as? CapsuleError) ?? .unknown(message: String(describing: error))
    }

    /// Probes the service: status → (if running) version + capabilities. Any thrown error
    /// resolves to `.unavailable` with a presentation-ready detail — never to "stopped"
    /// or an empty success.
    public func refreshStatus() async {
        health = .checking
        do {
            let runState = try await backend.systemStatus()
            switch runState {
            case .stopped:
                compatibilityWarning = nil
                health = .stopped
            case .running:
                let version = try await backend.version()
                let capabilities = try await backend.capabilities()
                compatibilityWarning = CapsuleDomain.compatibilityWarning(
                    forClient: version.client, server: version.server)
                health = .running(
                    version: SystemVersion(
                        client: Self.concise(version.client),
                        server: version.server.map(Self.concise)
                    ),
                    features: Self.features(from: capabilities)
                )
                onActivity("System running (client \(version.client)).")
            }
        } catch {
            let detail = normalize(error).detail
            onActivity("System unavailable: \(detail.title)")
            health = .unavailable(detail)
        }
    }

    /// Starts the service, then re-probes so the banner reflects the new state. When a task
    /// center is wired, the start registers an Activity task (so the long boot is visible,
    /// cancellable, and its raw transcript is kept); either way the banner is driven by a
    /// fresh re-probe, so a failed start surfaces as `.unavailable`/`.stopped` from reality
    /// rather than a reconstructed error.
    public func startServices() async {
        health = .checking
        guard let taskCenter else {
            do {
                try await backend.startSystem()
                onActivity("Started container services.")
                await refreshStatus()
            } catch {
                health = .unavailable(normalize(error).detail)
            }
            return
        }
        let task = taskCenter.runAsync(
            kind: .systemStart, title: "Start container services",
            invocation: CommandInvocation(CLICommand.startSystem())
        ) { [backend] in try await backend.startSystem() }
        await task.wait()
        if case .succeeded = task.state { onActivity("Started container services.") }
        await refreshStatus()
    }

    /// Stops the service, then re-probes.
    public func stopServices() async {
        do {
            try await backend.stopSystem()
            onActivity("Stopped container services.")
            await refreshStatus()
        } catch {
            health = .unavailable(normalize(error).detail)
        }
    }

    /// Maps backend capability flags into the UI-facing feature mirror by raw value.
    private static func features(from capabilities: BackendCapabilities) -> Set<SystemFeature> {
        Set(capabilities.features.compactMap { SystemFeature(rawValue: $0.rawValue) })
    }

    /// Reduces a possibly-noisy version string ("container-apiserver version 1.0.0 (build:
    /// release, commit: …)") to a concise "major.minor.patch" for the banner, falling back
    /// to the original text when no version-like substring is present.
    private static func concise(_ raw: String) -> String {
        guard let version = SemanticVersion(parsing: raw) else { return raw }
        return "\(version.major).\(version.minor).\(version.patch)"
    }
}
