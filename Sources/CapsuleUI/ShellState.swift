//
//  ShellState.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation
import Observation

/// Which tab the bottom Activity pane is showing.
public enum ActivityTab: String, CaseIterable, Identifiable, Sendable {
    case logs
    case tasks
    case progress

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .logs: return "Logs"
        case .tasks: return "Tasks"
        case .progress: return "Progress"
        }
    }

    public var symbolName: String {
        switch self {
        case .logs: return "text.alignleft"
        case .tasks: return "checklist"
        case .progress: return "chart.bar"
        }
    }
}

/// View-only shell state shared between the scene and the menu commands: sidebar
/// selection and the visibility of the inspector and the bottom Activity pane. Kept
/// separate from the domain models so toggling a pane never touches backend state.
@MainActor
@Observable
public final class ShellState {
    public var selection: SidebarSection
    public var inspectorPresented: Bool
    public var activityPanePresented: Bool
    public var activityTab: ActivityTab
    /// Recent activity lines (newest last), shown in the Activity pane's Logs tab.
    public private(set) var activityLog: [String]

    /// Caps the retained activity lines so the pane never grows without bound.
    private let activityLogLimit = 200

    public init(
        selection: SidebarSection = .containers,
        inspectorPresented: Bool = true,
        activityPanePresented: Bool = true,
        activityTab: ActivityTab = .logs,
        activityLog: [String] = []
    ) {
        self.selection = selection
        self.inspectorPresented = inspectorPresented
        self.activityPanePresented = activityPanePresented
        self.activityTab = activityTab
        self.activityLog = activityLog
    }

    /// Appends an activity line, trimming the oldest entries past the retention cap.
    public func appendActivity(_ line: String) {
        activityLog.append(line)
        if activityLog.count > activityLogLimit {
            activityLog.removeFirst(activityLog.count - activityLogLimit)
        }
    }

    public func toggleInspector() { inspectorPresented.toggle() }
    public func toggleActivityPane() { activityPanePresented.toggle() }

    /// Reveals the Activity pane's Logs tab — the destination for the "Open Logs"
    /// recovery action.
    public func revealLogs() {
        activityPanePresented = true
        activityTab = .logs
    }
}
