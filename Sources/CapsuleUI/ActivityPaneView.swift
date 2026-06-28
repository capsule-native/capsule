//
//  ActivityPaneView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The persistent bottom utility pane: a tab strip for Logs / Tasks / Progress plus an
//  embedded-terminal tab that appears while a session is live. The terminal tab grows the
//  pane to a drag-resizable height; the read-only attach console overlays the other tabs.
//  The terminal surface stays mounted while a session lives (even when another tab is
//  showing) so switching tabs never tears down its PTY / kills the shell.

import AppKit
import CapsuleDomain
import SwiftUI

struct ActivityPaneView: View {
    @Bindable var shell: ShellState
    /// Recent activity lines (newest last) surfaced by the system model.
    let activityLog: [String]
    /// The long-operation tasks (pull/push/save/load) shown in the Tasks/Progress tabs.
    var taskCenter: TaskCenter?
    /// The active read-only attach session, if any (takes over the pane content).
    var attachSession: AttachSession?
    var terminalAvailable: Bool = false
    /// The engine that renders the embedded terminal surface (nil in previews/tests).
    var terminalSurfaceProvider: (any TerminalSurfaceProviding)?
    var onDetach: () -> Void = {}
    var onRetryAttach: () -> Void = {}
    var onOpenShell: () -> Void = {}
    var onCloseTerminal: () -> Void = {}

    @State private var dragStartHeight: Double?

    private var showingTerminal: Bool {
        shell.activityTab == .terminal && shell.terminalSession != nil
    }

    private var visibleTabs: [ActivityTab] {
        shell.terminalSession == nil
            ? ActivityTab.baseCases : ActivityTab.baseCases + [.terminal]
    }

    var body: some View {
        VStack(spacing: 0) {
            resizeDivider
            header
            Divider()
            ZStack {
                // Base layer: the read-only attach console or the normal tab content.
                Group {
                    if let attachSession {
                        AttachConsoleView(
                            session: attachSession, terminalAvailable: terminalAvailable,
                            onDetach: onDetach, onRetry: onRetryAttach, onOpenShell: onOpenShell)
                    } else {
                        content
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Terminal layer: stays mounted whenever a session lives (so its PTY
                // survives tab switches); shown opaque only on the Terminal tab.
                if let session = shell.terminalSession {
                    terminalArea(session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .opacity(showingTerminal ? 1 : 0)
                        .allowsHitTesting(showingTerminal)
                }
            }
        }
        .frame(height: showingTerminal ? shell.terminalPaneHeight : 160)
        .background(CapsuleColors.activitySurface)
    }

    /// The top divider doubles as a drag handle while the terminal tab grows the pane.
    private var resizeDivider: some View {
        Divider()
            .overlay {
                if showingTerminal {
                    Color.clear
                        .frame(height: 8)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let start = dragStartHeight ?? shell.terminalPaneHeight
                                    if dragStartHeight == nil { dragStartHeight = start }
                                    shell.terminalPaneHeight =
                                        min(max(start - value.translation.height, 160), 600)
                                }
                                .onEnded { _ in dragStartHeight = nil })
                }
            }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Activity", selection: $shell.activityTab) {
                ForEach(visibleTabs) { tab in
                    Label(tab.title, systemImage: tab.symbolName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            Button {
                shell.toggleActivityPane()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Hide the Activity pane")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func terminalArea(_ session: TerminalSessionState) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(session.request.title, systemImage: "terminal")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close", action: onCloseTerminal)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            ZStack {
                if let terminalSurfaceProvider {
                    terminalSurfaceProvider
                        .makeSurface(for: session.request) { status in
                            session.exit = status
                        }
                        .id(session.surfaceID)
                } else {
                    placeholder("Terminal unavailable", systemImage: "terminal")
                }
                if let exit = session.exit {
                    exitBanner(exit, session: session)
                }
            }
        }
        .background(CapsuleColors.activitySurface)
    }

    private func exitBanner(
        _ status: TerminalExitStatus,
        session: TerminalSessionState
    ) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Text(status.bannerText).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Restart") { session.restart() }
                Button("Close", action: onCloseTerminal)
            }
            .padding(8)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch shell.activityTab {
        case .logs:
            logsList
        case .tasks:
            tasksList
        case .progress:
            progressList
        case .terminal:
            placeholder("No terminal session", systemImage: "terminal")
        }
    }

    @ViewBuilder
    private var tasksList: some View {
        let tasks = taskCenter?.tasks ?? []
        if tasks.isEmpty {
            placeholder("No tasks yet", systemImage: "checklist")
        } else {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Clear Finished") { taskCenter?.clearFinished() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .disabled(!tasks.contains { !$0.state.isActive })
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(tasks) { task in
                            TaskTranscriptView(
                                task: task,
                                onRetry: { taskCenter?.retry(task) },
                                onCancel: { taskCenter?.cancel(task) })
                            Divider()
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    @ViewBuilder
    private var progressList: some View {
        let active = taskCenter?.activeTasks ?? []
        if active.isEmpty {
            placeholder("No active transfers", systemImage: "chart.bar")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(active) { task in
                        HStack(spacing: 10) {
                            Label(task.title, systemImage: task.kind.symbolName)
                                .font(.caption)
                            Spacer()
                            if case let .running(progress) = task.state, let progress {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                                    .frame(width: 120)
                            } else {
                                ProgressView().controlSize(.small)
                            }
                            if task.isCancellable {
                                Button("Stop", role: .destructive) { taskCenter?.cancel(task) }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
    }

    private var logsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if activityLog.isEmpty {
                    Text("Activity will appear here.")
                        .foregroundStyle(.secondary)
                        .padding(8)
                } else {
                    ForEach(Array(activityLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func placeholder(_ title: String, systemImage: String) -> some View {
        VStack {
            Spacer()
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
