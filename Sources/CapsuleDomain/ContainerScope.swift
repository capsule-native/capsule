//
//  ContainerScope.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`.

import Foundation

/// A coarse filter over a container's lifecycle state.
public enum ContainerStateFilter: String, Sendable, Codable, CaseIterable, Identifiable {
    case all
    case running
    case stopped
    case created

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All"
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .created: return "Created"
        }
    }

    /// Whether a container's state passes this filter.
    public func matches(_ state: ContainerState) -> Bool {
        switch self {
        case .all: return true
        case .running: return state == .running
        case .stopped: return state == .stopped
        case .created: return state == .created
        }
    }
}

/// A named, saveable view over the container list: a state filter plus a captured search
/// term. Built-in scopes are constants; user scopes are saved copies persisted via a
/// ``ScopeStore``.
public struct ContainerScope: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var stateFilter: ContainerStateFilter
    public var searchTerm: String

    public init(id: String, name: String, stateFilter: ContainerStateFilter, searchTerm: String) {
        self.id = id
        self.name = name
        self.stateFilter = stateFilter
        self.searchTerm = searchTerm
    }

    public static let all = ContainerScope(
        id: "builtin.all", name: "All", stateFilter: .all, searchTerm: "")
    public static let running = ContainerScope(
        id: "builtin.running", name: "Running", stateFilter: .running, searchTerm: "")
    public static let stopped = ContainerScope(
        id: "builtin.stopped", name: "Stopped", stateFilter: .stopped, searchTerm: "")

    /// The scopes always offered, in display order.
    public static let builtIns: [ContainerScope] = [.all, .running, .stopped]
}
