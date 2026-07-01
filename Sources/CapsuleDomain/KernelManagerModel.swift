//
//  KernelManagerModel.swift
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

/// The source mode the user has selected in the Kernel Setup sheet.
public enum KernelSourceMode: String, Sendable, CaseIterable, Identifiable {
    case recommended, localFile, remoteTar
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .recommended: return "Recommended (safe)"
        case .localFile: return "Local file"
        case .remoteTar: return "Remote tar"
        }
    }
}

/// Domain model for the Kernel Setup sheet. Owns the draft inputs, derives validation,
/// builds the `commandPreview`, and fires the install task via ``TaskCenter``.
@MainActor
@Observable
public final class KernelManagerModel {

    // MARK: - Draft

    /// Mutable inputs that the sheet binds to.
    public struct Draft {
        public var mode: KernelSourceMode = .recommended
        public var binaryPath = ""
        public var tarURL = ""
        public var tarMember = ""
        /// Raw-value string from ``KernelArch`` (e.g. "arm64", "amd64") kept as a `String`
        /// so CapsuleUI does not need to import CapsuleBackend to name the type.
        public var arch: String = KernelArch.arm64.rawValue
        public var force = false

        public init() {}
    }

    public var draft = Draft()

    // MARK: - Derived state

    /// Summary line pulled from `systemProperties()` after `loadCurrent()`.
    public private(set) var currentKernelSummary: String?

    /// Architecture choices for the UI picker (raw-value strings matching ``KernelArch``).
    /// Exposed here so ``CapsuleUI`` does not need to import CapsuleBackend to enumerate them.
    public static let archOptions: [String] = KernelArch.allCases.map(\.rawValue)

    /// Static guidance shown below the Install button.
    public let recoveryGuidance =
        "Installing an incompatible kernel can stop containers and machines from booting. "
        + "If that happens, restore a known-good kernel with the Recommended option, or run "
        + "`container system kernel set --recommended` in Terminal."

    // MARK: - Init

    private let backend: any ContainerBackend
    private let taskCenter: TaskCenter
    private let normalize: @Sendable (any Error) -> CapsuleError

    public init(
        backend: any ContainerBackend,
        taskCenter: TaskCenter,
        normalize: @escaping @Sendable (any Error) -> CapsuleError =
            SystemStatusModel.defaultNormalize
    ) {
        self.backend = backend
        self.taskCenter = taskCenter
        self.normalize = normalize
    }

    // MARK: - Computed

    private var configuration: KernelConfiguration {
        let source: KernelSource
        switch draft.mode {
        case .recommended:
            source = .recommended
        case .localFile:
            source = .localBinary(path: draft.binaryPath)
        case .remoteTar:
            source = .remoteTar(
                url: draft.tarURL,
                member: draft.tarMember.isEmpty ? nil : draft.tarMember)
        }
        let arch = KernelArch(rawValue: draft.arch) ?? .arm64
        return KernelConfiguration(source: source, arch: arch, force: draft.force)
    }

    /// Non-nil when the current draft cannot be submitted.
    public var validationMessage: String? {
        switch draft.mode {
        case .recommended:
            return nil
        case .localFile:
            return draft.binaryPath.isEmpty ? "Choose a kernel file." : nil
        case .remoteTar:
            return draft.tarURL.isEmpty ? "Enter a tar archive URL or path." : nil
        }
    }

    /// The faithful kernel-set invocation the user would type.
    public var commandInvocation: CommandInvocation {
        CommandInvocation(configuration.arguments)
    }

    /// The equivalent shell command (redacted), derived from `commandInvocation`.
    public var commandPreview: String { commandInvocation.displayString }

    // MARK: - Actions

    /// Reads the current kernel from `systemProperties()` and populates `currentKernelSummary`.
    /// Errors are normalized via the injected `normalize` closure; they are not surfaced in the
    /// UI today but are no longer silently swallowed.
    public func loadCurrent() async {
        do {
            let props = try await backend.systemProperties()
            if let k = props.section("kernel") {
                let path = k.entries.first { $0.key == "binaryPath" }?.value
                let url = k.entries.first { $0.key == "url" }?.value
                currentKernelSummary = path ?? url
            }
        } catch {
            // Normalize so every error passes through the app's error domain; nothing in
            // the UI currently surfaces loadCurrent errors, so we swallow after normalizing.
            _ = normalize(error)
        }
    }

    /// Fires the kernel install as a streaming `TaskCenter` operation.
    /// On success, refreshes ``currentKernelSummary`` so the Preferences window
    /// reflects the newly installed kernel without requiring a close/reopen.
    public func install() {
        let config = configuration
        let backend = self.backend
        taskCenter.runStreaming(
            kind: .systemKernelInstall,
            title: "Install Kernel",
            onSuccess: { [weak self] in await self?.loadCurrent() }
        ) { [backend] in
            backend.setKernel(config)
        }
    }
}
