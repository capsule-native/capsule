//
//  LogsModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Backs the logs pane
//  and the detachable log window: a scrollback buffer fed by `container logs` (follow or a
//  bounded snapshot), a case-insensitive search filter, and a saveable transcript.

import CapsuleBackend
import Foundation
import Observation

@MainActor
@Observable
public final class LogsModel {
    public private(set) var lines: [LogLine] = []
    public private(set) var containerID: String?
    public private(set) var isStreaming = false
    public var follow = true
    public var tail: Int?
    public var boot = false
    public var searchText = ""

    private let backend: any ContainerBackend
    private var nextLineID = 0
    private var task: Task<Void, Never>?

    public init(backend: any ContainerBackend) {
        self.backend = backend
    }

    /// The lines matching the current search (case-insensitive substring); all lines when the
    /// search is empty.
    public var filteredLines: [LogLine] {
        guard !searchText.isEmpty else { return lines }
        return lines.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    /// The full (unfiltered) buffer joined for saving/copying.
    public var transcriptText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    /// Starts (or restarts) log capture for `id`: a live follow stream, or a bounded snapshot
    /// when `follow` is off.
    public func start(id: String) {
        stop()
        containerID = id
        lines = []
        nextLineID = 0
        if follow {
            isStreaming = true
            task = Task { [weak self, backend] in
                guard let self else { return }
                do {
                    for try await line in backend.followLogs(container: id) {
                        self.append(line)
                    }
                } catch {
                    // Stream ended or was cancelled; the buffer keeps what it captured.
                }
                self.isStreaming = false
            }
        } else {
            task = Task { [weak self, backend, tail, boot] in
                guard let self else { return }
                let fetched =
                    (try? await backend.fetchLogs(container: id, tail: tail, boot: boot)) ?? []
                for line in fetched { self.append(line) }
            }
        }
    }

    /// Stops any active capture.
    public func stop() {
        task?.cancel()
        task = nil
        isStreaming = false
    }

    /// Awaits the in-flight load/stream (tests and any caller needing completion).
    public func waitForLoad() async {
        await task?.value
    }

    private func append(_ line: OutputLine) {
        nextLineID += 1
        lines.append(LogLine(id: nextLineID, source: line.source, text: line.text))
    }
}
