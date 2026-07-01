//
//  RunModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Owns the Quick Run
//  flow: a UI-friendly draft, validation into a `RunConfiguration`, a live command preview
//  (the "Run Inspector"), and the two run paths — detached (an Activity task) and
//  attached/TTY (an embedded-terminal session). A failed detached run keeps triage state.

import CapsuleBackend
import Foundation
import Observation

/// A UI-friendly draft of a run: raw text rows the model trims/validates into a config.
public struct RunDraft: Sendable, Equatable, Codable {
    public var image: String = ""
    public var name: String = ""
    public var command: String = ""
    public var workdir: String = ""
    /// `KEY=value` rows; blank rows are ignored.
    public var envRows: [String] = []
    /// `host:container[/proto]` rows; blank rows are ignored.
    public var portRows: [String] = []
    /// `host:container[:ro]` rows; blank rows are ignored.
    public var volumeRows: [String] = []
    public var interactive: Bool = false
    public var remove: Bool = false
    public var detach: Bool = false

    public init() {}

    public init(image: String) {
        self.image = image
    }
}

@MainActor
@Observable
public final class RunModel {
    public var draft = RunDraft()
    /// The configuration of the most recent failed detached run, for the triage panel.
    public private(set) var lastFailedConfig: RunConfiguration?
    /// The most recent failed detached-run task (its transcript drives Inspect Logs).
    public private(set) var lastFailedTask: OperationTask?
    /// The user's saved run presets, loaded from the injected ``PresetStore``.
    public private(set) var runPresets: [SavedRunPreset] = []

    private let backend: any ContainerBackend
    private let taskCenter: TaskCenter
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void
    private let reloadList: @MainActor () async -> Void
    private let terminalAvailable: @MainActor () -> Bool
    private let launchTerminal: @MainActor (TerminalRequest) -> Void
    private let copyCommand: @MainActor ([String]) -> Void
    private let presetStore: any PresetStore

    public init(
        backend: any ContainerBackend,
        taskCenter: TaskCenter,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in },
        reloadList: @escaping @MainActor () async -> Void = {},
        terminalAvailable: @escaping @MainActor () -> Bool = { false },
        launchTerminal: @escaping @MainActor (TerminalRequest) -> Void = { _ in },
        copyCommand: @escaping @MainActor ([String]) -> Void = { _ in },
        presetStore: any PresetStore = InMemoryPresetStore()
    ) {
        self.backend = backend
        self.taskCenter = taskCenter
        self.normalize = normalize
        self.onActivity = onActivity
        self.reloadList = reloadList
        self.terminalAvailable = terminalAvailable
        self.launchTerminal = launchTerminal
        self.copyCommand = copyCommand
        self.presetStore = presetStore
    }

    /// Resets the draft, optionally prefilling the image (the contextual "Run Image…" path).
    public func reset(image: String = "") {
        draft = image.isEmpty ? RunDraft() : RunDraft(image: image)
        lastFailedConfig = nil
        lastFailedTask = nil
    }

    /// Validates the draft into a `RunConfiguration`, or returns the first field error.
    public func validatedConfiguration() -> Result<RunConfiguration, CapsuleError> {
        let image = draft.image.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !image.isEmpty else {
            return .failure(.invalidInput(field: "image", message: "Enter an image to run."))
        }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let workdir = draft.workdir.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = RunConfiguration(
            image: image,
            name: name.isEmpty ? nil : name,
            command: CommandTokenizer.tokenize(draft.command),
            env: cleaned(draft.envRows),
            publishPorts: cleaned(draft.portRows),
            volumes: cleaned(draft.volumeRows),
            workdir: workdir.isEmpty ? nil : workdir,
            user: nil,
            interactive: draft.interactive,
            tty: draft.interactive,
            detach: draft.detach && !draft.interactive,
            remove: draft.remove)
        return .success(config)
    }

    /// The faithful `container run …` invocation — the "Run Inspector". Falls back to
    /// `container run` while the image is empty so the field never shows a half-built command.
    public var commandInvocation: CommandInvocation {
        switch validatedConfiguration() {
        case let .success(config):
            return CommandInvocation(config.arguments)
        case .failure:
            return CommandInvocation(["run"])
        }
    }

    /// The redacted, space-joined preview string. Kept as a `String` accessor for call-site
    /// compatibility; now derives from `commandInvocation` so the preview cannot drift.
    public var commandPreview: String { commandInvocation.displayString }

    /// Runs the container attached with a TTY in the embedded terminal (or copies the command
    /// when the terminal is unavailable). Forces `-i -t` and clears `--detach`.
    public func runInTerminal() {
        guard case var .success(config) = validatedConfiguration() else { return }
        config.interactive = true
        config.tty = true
        config.detach = false
        let argv = ["container"] + config.arguments
        let request = TerminalRequest(
            containerID: nil, title: "Run · \(config.image)", argv: argv, kind: .runInteractive)
        if terminalAvailable() {
            launchTerminal(request)
        } else {
            copyCommand(argv)
        }
    }

    /// Runs the container detached as an Activity task; reloads the container list on success
    /// and keeps triage state on failure.
    @discardableResult
    public func runDetached() -> OperationTask? {
        guard case var .success(config) = validatedConfiguration() else { return nil }
        config.detach = true
        config.interactive = false
        config.tty = false
        onActivity("Running \(config.image)…")
        let task = taskCenter.runAsync(
            kind: .run, title: "Run \(config.image)",
            invocation: CommandInvocation(config.arguments),
            onSuccess: { [reloadList] in await reloadList() }
        ) { [backend] in
            _ = try await backend.runContainer(config)
        }
        // Record triage state as soon as the task settles into a failure.
        Task { [weak self] in
            await task.wait()
            guard let self else { return }
            if case .failed = task.state {
                self.lastFailedConfig = config
                self.lastFailedTask = task
            }
        }
        return task
    }

    /// The image reference of the last failed run — the Resolve Image triage action pulls it.
    public var resolveImageReference: String? { lastFailedConfig?.image }

    /// Re-runs the last failed configuration in the embedded terminal (the triage retry).
    public func retryInTerminal() {
        guard let config = lastFailedConfig else { return }
        draft.image = config.image
        runInTerminal()
    }

    // MARK: Saved presets

    /// Loads saved run presets from the store into ``runPresets``.
    public func loadPresets() {
        runPresets = presetStore.loadRunPresets()
    }

    /// Saves the current draft as a new named preset and persists the list.
    public func savePreset(name: String) {
        let preset = SavedRunPreset(name: name, draft: draft)
        runPresets.append(preset)
        presetStore.saveRunPresets(runPresets)
        onActivity("Saved run preset “\(name)”.")
    }

    /// Removes a preset and persists the updated list.
    public func deletePreset(_ preset: SavedRunPreset) {
        runPresets.removeAll { $0.id == preset.id }
        presetStore.saveRunPresets(runPresets)
    }

    /// Loads a preset's draft into the sheet, ready to run.
    public func apply(_ preset: SavedRunPreset) {
        draft = preset.draft
    }

    private func cleaned(_ rows: [String]) -> [String] {
        rows.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
