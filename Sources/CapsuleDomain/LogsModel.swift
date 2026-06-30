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

// MARK: - LogSource

/// A source-agnostic seam for log streaming and fetching. Lets `LogsModel` drive both
/// container logs and machine logs through identical code paths.
///
/// `fetch` parameters: `(id, tail, lastMinutes, boot)`
/// - `tail` — line-count limit used by container and machine sources (maps to `--tail`)
/// - `lastMinutes` — time window in minutes used by the system source (maps to `--last <n>m`);
///   system sources ignore `tail`, all other sources ignore `lastMinutes`.
public struct LogSource: Sendable {
    public var follow: @Sendable (String, Bool) -> AsyncThrowingStream<OutputLine, Error>
    public var fetch: @Sendable (String, Int?, Int?, Bool) async throws -> [OutputLine]

    public init(
        follow: @escaping @Sendable (String, Bool) -> AsyncThrowingStream<OutputLine, Error>,
        fetch: @escaping @Sendable (String, Int?, Int?, Bool) async throws -> [OutputLine]
    ) {
        self.follow = follow
        self.fetch = fetch
    }

    /// A source that reads container logs via `followLogs` / `fetchLogs`.
    public static func container(_ backend: any ContainerBackend) -> LogSource {
        LogSource(
            follow: { id, _ in backend.followLogs(container: id) },
            fetch: { id, tail, _, boot in
                try await backend.fetchLogs(container: id, tail: tail, boot: boot)
            }
        )
    }

    /// A source that reads machine logs via `followMachineLogs` / `fetchMachineLogs`.
    public static func machine(_ backend: any ContainerBackend) -> LogSource {
        LogSource(
            follow: { id, boot in backend.followMachineLogs(id: id, boot: boot) },
            fetch: { id, tail, _, boot in
                try await backend.fetchMachineLogs(id: id, tail: tail, boot: boot)
            }
        )
    }

    /// A source that reads the system service logs.
    /// `id`/`tail`/`boot` are ignored; `lastMinutes` (Int?) maps to `--last <n>m` (nil → "5m").
    public static func system(_ backend: any ContainerBackend) -> LogSource {
        LogSource(
            follow: { _, _ in backend.followSystemLogs() },
            fetch: { _, _, lastMinutes, _ in
                let last = lastMinutes.map { "\($0)m" } ?? "5m"
                return try await backend.fetchSystemLogs(last: last)
            }
        )
    }
}

// MARK: - LogsModel

@MainActor
@Observable
public final class LogsModel {
    public private(set) var lines: [LogLine] = []
    public private(set) var containerID: String?
    public private(set) var isStreaming = false
    public var follow = true
    public var tail: Int?
    /// Minutes window used exclusively by the system log source (`LogSource.system`).
    /// Bind UI controls to this—not to `tail`—when building a system-logs view.
    public var lastMinutes: Int?
    public var boot = false
    public var searchText = ""

    private let source: LogSource
    private var nextLineID = 0
    private var task: Task<Void, Never>?

    /// Primary initialiser: drives log capture through the given `LogSource`.
    public init(source: LogSource) {
        self.source = source
    }

    /// Back-compat convenience: uses a container log source backed by `backend`.
    /// Existing call sites (container logs pane, detachable window) compile unchanged.
    public init(backend: any ContainerBackend) {
        self.source = .container(backend)
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
            task = Task { [weak self, source, boot] in
                guard let self else { return }
                do {
                    for try await line in source.follow(id, boot) {
                        self.append(line)
                    }
                } catch {
                    // Stream ended or was cancelled; the buffer keeps what it captured.
                }
                // Only a naturally-ended stream clears the flag. A cancelled task (replaced by
                // a restart) must NOT clobber the successor's `isStreaming = true`.
                if !Task.isCancelled { self.isStreaming = false }
            }
        } else {
            task = Task { [weak self, source, tail, lastMinutes, boot] in
                guard let self else { return }
                let fetched =
                    (try? await source.fetch(id, tail, lastMinutes, boot)) ?? []
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
