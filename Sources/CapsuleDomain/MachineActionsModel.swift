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
    public var confirmation: ConfirmationRequest?
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
            let task = taskCenter.runStreaming(
                kind: .machineCreate, title: "Create machine \(name)",
                onSuccess: { [weak self] in await self?.reloadList() }
            ) { [backend] in backend.createMachine(config) }
            await task.wait()
            guard case .succeeded = task.state else { return false }
        } else {
            do { for try await _ in backend.createMachine(config) {} } catch {
                notice = LifecycleNotice(detail: normalize(error).detail); return false
            }
            await reloadList()
        }
        onActivity("Created machine \u{201c}\(name)\u{201d}.")
        banner = MachineBanner(kind: .created(name: name))
        return true
    }
}
