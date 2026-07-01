//
//  ShellState.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import Foundation
import Observation

/// Which tab the bottom Activity pane is showing.
public enum ActivityTab: String, CaseIterable, Identifiable, Sendable {
    case logs
    case tasks
    case progress
    case terminal

    public var id: String { rawValue }

    /// The tabs always present. `.terminal` appears only while a session is live, so it is
    /// excluded here and added by the pane on demand.
    public static let baseCases: [ActivityTab] = [.logs, .tasks, .progress]

    public var title: String {
        switch self {
        case .logs: return "Logs"
        case .tasks: return "Tasks"
        case .progress: return "Progress"
        case .terminal: return "Terminal"
        }
    }

    public var symbolName: String {
        switch self {
        case .logs: return "text.alignleft"
        case .tasks: return "checklist"
        case .progress: return "chart.bar"
        case .terminal: return "terminal"
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
    /// The single active embedded-terminal session, or nil.
    public var terminalSession: TerminalSessionState?
    /// Height of the Activity pane while the Terminal tab is showing (drag-resizable).
    public var terminalPaneHeight: Double
    /// Which System sub-tab is shown (deep-linked by `Open System Logs` / `Reclaim Disk Space`).
    public var systemTab: SystemTab
    /// Whether the ⌘K command palette overlay is presented.
    public var commandPalettePresented: Bool
    /// The app-level sheet to present (palette/menu path), or nil.
    public var pendingSheet: AppSheetIntent?

    /// Caps the retained activity lines so the pane never grows without bound.
    private let activityLogLimit = 200

    public init(
        selection: SidebarSection = .containers,
        inspectorPresented: Bool = true,
        activityPanePresented: Bool = true,
        activityTab: ActivityTab = .logs,
        activityLog: [String] = [],
        terminalSession: TerminalSessionState? = nil,
        terminalPaneHeight: Double = 320,
        systemTab: SystemTab = .overview,
        commandPalettePresented: Bool = false,
        pendingSheet: AppSheetIntent? = nil
    ) {
        self.selection = selection
        self.inspectorPresented = inspectorPresented
        self.activityPanePresented = activityPanePresented
        self.activityTab = activityTab
        self.activityLog = activityLog
        self.terminalSession = terminalSession
        self.terminalPaneHeight = terminalPaneHeight
        self.systemTab = systemTab
        self.commandPalettePresented = commandPalettePresented
        self.pendingSheet = pendingSheet
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

    /// Deep-links to a System sub-tab: selects the System surface and switches its tab.
    public func openSystem(tab: SystemTab) {
        selection = .system
        systemTab = tab
    }

    /// Shows/hides the ⌘K command palette.
    public func toggleCommandPalette() { commandPalettePresented.toggle() }

    /// Requests an app-level sheet (presented by `AppShellView`).
    public func present(_ intent: AppSheetIntent) { pendingSheet = intent }

    /// Reveals the Activity pane's Logs tab — the destination for the "Open Logs"
    /// recovery action.
    public func revealLogs() {
        activityPanePresented = true
        activityTab = .logs
    }

    /// Opens an embedded-terminal session, revealing the pane on its Terminal tab.
    public func openTerminal(_ request: TerminalRequest) {
        terminalSession = TerminalSessionState(request: request)
        activityPanePresented = true
        activityTab = .terminal
    }

    /// Ends the active terminal session and returns the pane to its Logs tab.
    public func closeTerminal() {
        terminalSession = nil
        if activityTab == .terminal { activityTab = .logs }
    }
}
