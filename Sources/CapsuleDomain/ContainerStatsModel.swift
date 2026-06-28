//
//  ContainerStatsModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. CPU% is computed
//  from consecutive cumulative samples; the poll-loop cadence lives in the adapter's stream.

import CapsuleBackend
import Foundation
import Observation

/// Owns container resource metrics: a one-shot snapshot mode and a live streaming mode that
/// restores cleanly on interrupt (no leaked task/process). CPU% is derived from consecutive
/// cumulative `cpuUsageUsec` samples with an epsilon guard against near-zero elapsed windows.
@MainActor
@Observable
public final class ContainerStatsModel {
    public private(set) var metrics: [String: ContainerMetrics] = [:]
    public private(set) var isStreaming = false

    private let backend: any ContainerBackend
    private let now: () -> Date
    private var streamTask: Task<Void, Never>?
    private var priorCPU: [String: (usec: UInt64, at: Double)] = [:]

    /// Minimum elapsed seconds before a CPU% delta is trusted.
    private let epsilon = 0.05

    public init(backend: any ContainerBackend, now: @escaping () -> Date = { Date() }) {
        self.backend = backend
        self.now = now
    }

    /// Fetches a one-shot snapshot for the given (non-empty) running ids.
    public func snapshot(ids: [String]) async {
        guard !ids.isEmpty else { return }
        guard let samples = try? await backend.containerStats(ids: ids) else { return }
        let at = Self.monotonicSeconds()
        for sample in samples { _ = ingest(sample, at: at) }
    }

    /// Begins live streaming for the given (non-empty) running ids; replaces any prior stream.
    public func startStreaming(ids: [String], interval: Duration = .seconds(2)) {
        stop()
        guard !ids.isEmpty else { return }
        isStreaming = true
        streamTask = Task { [weak self] in
            guard let stream = self?.backend.streamContainerStats(ids: ids, interval: interval)
            else { return }
            do {
                for try await batch in stream {
                    guard let self else { return }
                    let at = Self.monotonicSeconds()
                    for sample in batch { _ = self.ingest(sample, at: at) }
                }
            } catch is CancellationError {
                // clean teardown
            } catch {
                // streaming stats failure is non-fatal; stop quietly
            }
            self?.isStreaming = false
        }
    }

    /// Cancels streaming and restores cleanly (no leaked task/process).
    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    // MARK: CPU% (single ingest point; `internal` so tests can drive it deterministically)

    @discardableResult
    func ingest(_ sample: ContainerStatsSample, at seconds: Double) -> ContainerMetrics {
        var cpuPercent: Double?
        if let usec = sample.cpuUsageUsec, let prior = priorCPU[sample.id] {
            let elapsed = seconds - prior.at
            if elapsed > epsilon, usec >= prior.usec {
                cpuPercent = Double(usec - prior.usec) / (elapsed * 1_000_000) * 100
            } else {
                cpuPercent = metrics[sample.id]?.cpuPercent  // hold the prior value
            }
        }
        // Advance the baseline only over a meaningful window so a burst of near-simultaneous
        // samples can't poison the next delta.
        if let usec = sample.cpuUsageUsec {
            if let prior = priorCPU[sample.id] {
                if seconds - prior.at > epsilon { priorCPU[sample.id] = (usec, seconds) }
            } else {
                priorCPU[sample.id] = (usec, seconds)
            }
        }
        let metric = ContainerMetrics(sample: sample, capturedAt: now(), cpuPercent: cpuPercent)
        metrics[sample.id] = metric
        return metric
    }

    private static func monotonicSeconds() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}
