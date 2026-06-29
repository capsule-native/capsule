//
//  MachineActionsModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Owns the
//  machine mutation operations (create, set, set-default, stop, delete, shell); later
//  tasks (B11-B14) append additional methods to this class.

import CapsuleBackend
import Foundation
import Observation

@MainActor
@Observable
public final class MachineActionsModel {
    // MARK: - Stored state

    public private(set) var busy: Set<String> = []
    public var notice: LifecycleNotice?
    public var banner: MachineBanner?
    public var pendingRestart: Set<String> = []

    // MARK: - Injected dependencies

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void
    private let reloadList: @MainActor () async -> Void
    private let currentState: @MainActor (String) -> MachineState
    private let terminalAvailable: @MainActor () -> Bool
    private let copyCommand: @MainActor ([String]) -> Void
    private let launchTerminal: @MainActor (TerminalRequest) -> Void
    private let taskCenter: TaskCenter?

    private var previousDefault: String?

    // MARK: - Init

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in },
        reloadList: @escaping @MainActor () async -> Void = {},
        currentState: @escaping @MainActor (String) -> MachineState = { _ in .unknown },
        terminalAvailable: @escaping @MainActor () -> Bool = { false },
        copyCommand: @escaping @MainActor ([String]) -> Void = { _ in },
        launchTerminal: @escaping @MainActor (TerminalRequest) -> Void = { _ in },
        taskCenter: TaskCenter? = nil
    ) {
        self.backend = backend
        self.normalize = normalize
        self.onActivity = onActivity
        self.reloadList = reloadList
        self.currentState = currentState
        self.terminalAvailable = terminalAvailable
        self.copyCommand = copyCommand
        self.launchTerminal = launchTerminal
        self.taskCenter = taskCenter
    }

    // MARK: - Validation / preview

    public func configuration(from draft: MachineDraft) -> MachineConfiguration {
        func trimmed(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t
        }
        return MachineConfiguration(
            image: draft.image.trimmingCharacters(in: .whitespacesAndNewlines),
            name: trimmed(draft.name),
            cpus: trimmed(draft.cpus).flatMap(Int.init),
            memory: trimmed(draft.memory),
            homeMount: trimmed(draft.homeMount),
            arch: trimmed(draft.arch), os: trimmed(draft.os), platform: trimmed(draft.platform),
            setDefault: draft.setDefault, noBoot: draft.noBoot)
    }

    public func commandPreview(for draft: MachineDraft) -> String {
        "container " + configuration(from: draft).arguments.joined(separator: " ")
    }

    public func createProblem(_ draft: MachineDraft) -> String? {
        MachineValidation.imageProblem(draft.image)
            ?? MachineValidation.cpusProblem(draft.cpus)
            ?? MachineValidation.memoryProblem(draft.memory)
            ?? MachineValidation.homeMountProblem(draft.homeMount)
    }

    public func canCreate(_ draft: MachineDraft) -> Bool { createProblem(draft) == nil }

    // MARK: - Settings (set)

    private func settings(from draft: MachineSettingsDraft) -> MachineSettings {
        func trimmed(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t
        }
        return MachineSettings(
            cpus: trimmed(draft.cpus).flatMap(Int.init), memory: trimmed(draft.memory),
            homeMount: trimmed(draft.homeMount))
    }

    public func settingsProblem(_ draft: MachineSettingsDraft) -> String? {
        MachineValidation.cpusProblem(draft.cpus)
            ?? MachineValidation.memoryProblem(draft.memory)
            ?? MachineValidation.homeMountProblem(draft.homeMount)
    }

    public func settingsPreview(name: String?, draft: MachineSettingsDraft) -> String {
        "container " + settings(from: draft).arguments(name: name).joined(separator: " ")
    }

    @discardableResult
    public func apply(settings draft: MachineSettingsDraft, to name: String) async -> Bool {
        if let problem = settingsProblem(draft) {
            notice = LifecycleNotice(
                detail: ErrorDetail(
                    title: "Can\u{2019}t update settings", explanation: problem,
                    recoveryActions: []))
            return false
        }
        busy.insert(name); defer { busy.remove(name) }
        do {
            try await backend.setMachine(name: name, settings: settings(from: draft))
            await reloadList()
            pendingRestart.insert(name)
            onActivity("Updated \u{201c}\(name)\u{201d}; restart to apply.")
            return true
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail); return false
        }
    }

    public func restartRequired(_ name: String) -> Bool { pendingRestart.contains(name) }
    public func clearRestart(_ name: String) { pendingRestart.remove(name) }

    // MARK: - Stop + Delete

    @discardableResult
    public func stop(_ name: String) async -> Bool {
        busy.insert(name); defer { busy.remove(name) }
        do {
            try await backend.stopMachine(id: name)
            await reloadList()
            pendingRestart.remove(name)
            onActivity("Stopped machine \u{201c}\(name)\u{201d}.")
            banner = MachineBanner(kind: .stopped(name: name))
            return true
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
            return false
        }
    }

    public func delete(_ name: String) async {
        busy.insert(name); defer { busy.remove(name) }
        do {
            try await backend.deleteMachine(id: name)
            pendingRestart.remove(name)
            await reloadList()
            onActivity("Deleted machine \u{201c}\(name)\u{201d}.")
        } catch { notice = LifecycleNotice(detail: normalize(error).detail) }
    }

    // MARK: - Set-default + revert

    @discardableResult
    public func makeDefault(_ name: String, previousDefault: String?) async -> Bool {
        busy.insert(name); defer { busy.remove(name) }
        do {
            try await backend.setDefaultMachine(id: name)
            self.previousDefault = previousDefault
            await reloadList()
            onActivity("Made \u{201c}\(name)\u{201d} the default machine.")
            banner = MachineBanner(kind: .madeDefault(name: name, previous: previousDefault))
            return true
        } catch { notice = LifecycleNotice(detail: normalize(error).detail); return false }
    }

    public func revertDefault() async {
        guard let prev = previousDefault else { return }
        do {
            try await backend.setDefaultMachine(id: prev)
            previousDefault = nil
            await reloadList()
            onActivity("Reverted default machine to \u{201c}\(prev)\u{201d}.")
            banner = nil
        } catch { notice = LifecycleNotice(detail: normalize(error).detail) }
    }

    // MARK: - Shell + implicit-boot

    public func shellArgv(name: String) -> [String] {
        var argv = ["container", "machine", "run", "-it"]
        if !name.isEmpty { argv += ["-n", name] }
        return argv
    }

    public func openShell(name: String) {
        if currentState(name) != .running {
            banner = MachineBanner(kind: .implicitBoot(name: name))
        }
        let request = TerminalRequest(
            containerID: nil, title: "Machine \u{00b7} \(name)", argv: shellArgv(name: name),
            kind: .execShell)
        if terminalAvailable() { launchTerminal(request) } else { copyCommand(request.argv) }
    }

    public func restartNow(_ name: String) async {
        guard await stop(name) else { return }
        clearRestart(name)
        openShell(name: name)
    }

    // MARK: - Logs factory

    /// Returns a pair of `LogsModel` instances pre-configured for machine logs:
    /// one for the boot log (`boot == true`) and one for the session log (`boot == false`).
    /// CapsuleUI calls this to avoid importing CapsuleBackend directly.
    public func makeLogsModels() -> (boot: LogsModel, session: LogsModel) {
        let boot = LogsModel(source: .machine(backend))
        boot.boot = true
        boot.follow = false
        let session = LogsModel(source: .machine(backend))
        session.boot = false
        session.follow = false
        return (boot, session)
    }

    // MARK: - Create

    @discardableResult
    public func create(draft: MachineDraft) async -> Bool {
        if let problem = createProblem(draft) {
            notice = LifecycleNotice(
                detail: ErrorDetail(
                    title: "Can\u{2019}t create machine",
                    explanation: problem, recoveryActions: []))
            return false
        }
        let config = configuration(from: draft)
        let name = config.name ?? config.image
        if let taskCenter {
            taskCenter.runStreaming(
                kind: .machineCreate, title: "Create machine \(name)",
                onSuccess: { [weak self] in
                    await self?.reloadList()
                    self?.onActivity("Created machine \u{201c}\(name)\u{201d}.")
                    self?.banner = MachineBanner(kind: .created(name: name))
                }
            ) { [backend] in backend.createMachine(config) }
            return true  // enqueued; the sheet dismisses and Activity shows progress
        }
        do { for try await _ in backend.createMachine(config) {} } catch {
            notice = LifecycleNotice(detail: normalize(error).detail); return false
        }
        await reloadList()
        onActivity("Created machine \u{201c}\(name)\u{201d}.")
        banner = MachineBanner(kind: .created(name: name))
        return true
    }
}
