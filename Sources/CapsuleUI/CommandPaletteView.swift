//
//  CommandPaletteView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The ⌘K command palette: a search field over the fuzzy-ranked CommandCatalog. Return runs
//  the first enabled match; selecting a row runs it and dismisses. Renders the exact same
//  actions the menu bar does, so the two surfaces cannot drift.

import CapsuleDomain
import SwiftUI

public struct CommandPaletteView: View {
    @Bindable private var shell: ShellState
    private let context: CommandContext
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    public init(shell: ShellState, context: CommandContext) {
        self.shell = shell
        self.context = context
    }

    /// Pure filter+rank used by the body (and unit-tested in isolation).
    public static func ranked(_ actions: [CommandAction], query: String) -> [CommandAction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return actions }
        return
            actions
            .enumerated()
            .compactMap { index, action -> (Int, CommandAction, Int)? in
                guard let score = FuzzyMatch.score(trimmed, action.title) else { return nil }
                return (index, action, score)
            }
            .sorted { $0.2 != $1.2 ? $0.2 < $1.2 : $0.0 < $1.0 }
            .map(\.1)
    }

    private var matches: [CommandAction] {
        CommandPaletteView.ranked(CommandCatalog.actions(context), query: query)
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextField("Run a command…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(16)
                .focused($searchFocused)
                .onSubmit(runFirst)

            Divider()

            List(matches) { action in
                Button {
                    run(action)
                } label: {
                    CommandPaletteRow(action: action)
                }
                .buttonStyle(.plain)
                .disabled(!action.isEnabled)
            }
            .listStyle(.plain)
        }
        .frame(width: 560, height: 420)
        .onAppear { searchFocused = true }
        .onExitCommand { shell.commandPalettePresented = false }
    }

    private func runFirst() {
        if let first = matches.first(where: { $0.isEnabled }) { run(first) }
    }

    /// Dismisses the palette FIRST, then runs the action on the next runloop tick. Running
    /// the action synchronously with the dismissal can race a second sheet the action
    /// presents (e.g. `shell.pendingSheet`): macOS can drop that sheet's presentation if it's
    /// requested while the palette's own sheet is still tearing down. Deferring is harmless
    /// for actions that don't present anything.
    private func run(_ action: CommandAction) {
        shell.commandPalettePresented = false
        DispatchQueue.main.async { action.run() }
    }
}

/// One palette row: symbol, title, optional hint subtitle, and a trailing shortcut glyph.
private struct CommandPaletteRow: View {
    let action: CommandAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.symbol)
                .frame(width: 20)
                .foregroundStyle(action.isEnabled ? .primary : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .foregroundStyle(action.isEnabled ? .primary : .secondary)
                if let subtitle = action.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let shortcut = action.shortcut {
                Text(shortcut.display)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
