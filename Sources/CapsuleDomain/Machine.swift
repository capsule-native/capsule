//
//  Machine.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import Foundation

public enum MachineState: String, Sendable, Equatable {
    case running, stopped, unknown
    public init(raw: String?) {
        switch raw?.lowercased() {
        case "running": self = .running
        case "stopped", "stop", "off": self = .stopped
        default: self = .unknown
        }
    }
    public var isRunning: Bool { self == .running }
    public var label: String {
        switch self {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .unknown: return "Unknown"
        }
    }
    public var symbolName: String {
        switch self {
        case .running: return "play.circle.fill"
        case .stopped: return "stop.circle"
        case .unknown: return "questionmark.circle"
        }
    }
}

public struct Machine: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var state: MachineState
    public var isDefault: Bool
    public var ipAddress: String?
    public var cpus: Int?
    public var memory: String?
    public var disk: String?
    public var homeMount: String?
    public var kernel: String?
    public var nestedVirtualization: Bool?
    public var createdAt: Date?

    public init(
        id: String, name: String, state: MachineState = .unknown, isDefault: Bool = false,
        ipAddress: String? = nil, cpus: Int? = nil, memory: String? = nil, disk: String? = nil,
        homeMount: String? = nil, kernel: String? = nil, nestedVirtualization: Bool? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id; self.name = name; self.state = state; self.isDefault = isDefault
        self.ipAddress = ipAddress; self.cpus = cpus; self.memory = memory; self.disk = disk
        self.homeMount = homeMount; self.kernel = kernel
        self.nestedVirtualization = nestedVirtualization; self.createdAt = createdAt
    }
}

extension Machine {
    public init(summary: MachineSummary) {
        self.init(
            id: summary.id, name: summary.name, state: MachineState(raw: summary.state),
            isDefault: summary.isDefault, ipAddress: summary.ipAddress, cpus: summary.cpus,
            memory: summary.memory, disk: summary.disk, homeMount: summary.homeMount,
            kernel: summary.kernel, nestedVirtualization: summary.nestedVirtualization,
            createdAt: summary.createdAt.flatMap(Container.parseDate))
    }
}
