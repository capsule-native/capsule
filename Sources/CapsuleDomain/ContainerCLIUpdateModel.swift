//
//  ContainerCLIUpdateModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Installing and
//  updating the `container` CLI itself cannot go through the container port (there is no
//  binary to run), so this model speaks the release port for downloads and hands
//  privileged updates to an injected Terminal closure — mirroring `DNSModel`'s seam.

import CapsuleBackend
import Foundation
import Observation

@MainActor
@Observable
public final class ContainerCLIUpdateModel {
    /// Where Apple's pkg installs its own updater script.
    public static let updaterScriptPath = "/usr/local/bin/update-container.sh"

    /// The latest-release lookup the About pane binds to.
    public enum LatestState: Sendable, Equatable {
        case idle
        case checking
        case available(String)
        case failed(String)
    }

    public private(set) var latest: LatestState = .idle
    /// The pkg URL the most recent successful install task downloaded (openable in
    /// Installer). Internal so the task's onSuccess can read it; tests observe the closure.
    private(set) var downloadedInstallerURL: URL?

    private let releaseSource: any ContainerReleaseSource
    private let taskCenter: TaskCenter
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void
    private let containerPath: String
    private let updaterScriptExists: () -> Bool
    private let openInstaller: @MainActor (URL) -> Void
    private let runScriptInTerminal: @MainActor (String) -> Void

    public init(
        releaseSource: any ContainerReleaseSource,
        taskCenter: TaskCenter,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in },
        containerPath: String,
        updaterScriptExists: @escaping () -> Bool,
        openInstaller: @escaping @MainActor (URL) -> Void,
        runScriptInTerminal: @escaping @MainActor (String) -> Void
    ) {
        self.releaseSource = releaseSource
        self.taskCenter = taskCenter
        self.normalize = normalize
        self.onActivity = onActivity
        self.containerPath = containerPath
        self.updaterScriptExists = updaterScriptExists
        self.openInstaller = openInstaller
        self.runScriptInTerminal = runScriptInTerminal
    }

    /// Whether Apple's updater script is present (drives the Update sheet's copy).
    public var updaterScriptAvailable: Bool { updaterScriptExists() }

    /// The exact handoff script the Update sheet previews.
    public var updateScriptPreview: String {
        Self.updateScript(containerPath: containerPath)
    }

    /// Looks up the latest release tag for the About pane. Serialized: a lookup already
    /// in flight wins.
    public func checkLatest() async {
        if case .checking = latest { return }
        latest = .checking
        do {
            let release = try await releaseSource.latestRelease()
            latest = .available(release.tag)
        } catch {
            latest = .failed(normalize(error).detail.explanation)
        }
    }

    /// Downloads the latest signed installer package as a cancellable Activity task and
    /// opens it in Installer on success. The user completes installation there (native
    /// administrator prompt + package signature validation).
    public func installLatest() {
        let source = releaseSource
        let directory = FileManager.default.temporaryDirectory
        downloadedInstallerURL = nil
        taskCenter.runStreaming(
            kind: .cliInstall,
            title: "Download container installer",
            onSuccess: { [weak self] in
                guard let self, let url = self.downloadedInstallerURL else { return }
                self.openInstaller(url)
                self.onActivity("Opened \(url.lastPathComponent) — finish installing there.")
            }
        ) {
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let release = try await source.latestRelease()
                        guard let asset = release.signedInstallerAsset else {
                            throw ContainerReleaseError.noSignedPackage(tag: release.tag)
                        }
                        continuation.yield(
                            OutputLine(source: .stdout, text: "Latest release: \(release.tag)"))
                        let destination = directory.appendingPathComponent(asset.name)
                        for try await line in source.downloadPackage(asset, to: destination) {
                            continuation.yield(line)
                        }
                        await MainActor.run { [weak self] in
                            self?.downloadedInstallerURL = destination
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        onActivity("Downloading the latest signed container installer from GitHub.")
    }

    /// Updates an installed CLI: hands Apple's updater script to Terminal (stop services →
    /// sudo update → restart on success). Falls back to the installer download when the
    /// script is missing (the pkg installs over the existing version).
    public func runUpdater() {
        guard updaterScriptExists() else {
            onActivity("Updater script not found — downloading the installer instead.")
            installLatest()
            return
        }
        runScriptInTerminal(Self.updateScript(containerPath: containerPath))
        onActivity("Opened Terminal to update the container CLI (requires administrator).")
    }

    /// The `.command` script body for the Terminal handoff. `system stop` is best-effort
    /// (the updater re-checks via launchctl and refuses to run over a live service);
    /// `system start` runs only after a successful update.
    public static func updateScript(containerPath: String) -> String {
        let container = shellQuoted(containerPath)
        let updater = shellQuoted(updaterScriptPath)
        return "#!/bin/sh\n"
            + "\(container) system stop\n"
            + "sudo \(updater) && \(container) system start\n"
    }

    /// Whether `installed` is at or beyond `latest`; unparsable/nil versions are treated
    /// as outdated so the UI errs toward offering the update.
    public static func isUpToDate(installed: String?, latest: String) -> Bool {
        guard let installed,
            let installedVersion = SemanticVersion(parsing: installed),
            let latestVersion = SemanticVersion(parsing: latest)
        else { return false }
        return !(installedVersion < latestVersion)
    }

    /// Single-quotes a token for safe inclusion in a `/bin/sh` command line.
    private static func shellQuoted(_ token: String) -> String {
        "'" + token.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
