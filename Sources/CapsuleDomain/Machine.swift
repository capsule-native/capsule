//
//  Machine.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

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
