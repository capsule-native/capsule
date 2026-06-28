//
//  BackendLifecycleTypes.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Foundation-only value types for the container lifecycle port methods. The domain maps
//  these into its own types before they reach the UI (the arch guard forbids Backend types
//  in CapsuleUI signatures).

import Foundation

/// Options for a graceful stop. `signal` is a raw token (e.g. "TERM") because the Backend
/// layer cannot import the domain's `ProcessSignal`.
public struct StopOptions: Sendable, Equatable {
    public var timeout: Int?
    public var signal: String?

    public init(timeout: Int? = nil, signal: String? = nil) {
        self.timeout = timeout
        self.signal = signal
    }

    /// The CLI defaults (TERM, then kill after 5 s).
    public static let `default` = StopOptions(timeout: nil, signal: nil)
    /// Immediate force via the non-destructive stop verb (`stop -t 0`).
    public static let forced = StopOptions(timeout: 0, signal: nil)
}

/// An all-optional mirror of the CLI's `ContainerStats` (verified against apple/container
/// source: only `id` is required; every metric is an optional cumulative `UInt64`). Carries
/// no CPU% and no timestamp — the domain computes/stamps both.
public struct ContainerStatsSample: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var cpuUsageUsec: UInt64?
    public var memoryUsageBytes: UInt64?
    public var memoryLimitBytes: UInt64?
    public var networkRxBytes: UInt64?
    public var networkTxBytes: UInt64?
    public var blockReadBytes: UInt64?
    public var blockWriteBytes: UInt64?
    public var numProcesses: UInt64?

    public init(
        id: String,
        cpuUsageUsec: UInt64? = nil,
        memoryUsageBytes: UInt64? = nil,
        memoryLimitBytes: UInt64? = nil,
        networkRxBytes: UInt64? = nil,
        networkTxBytes: UInt64? = nil,
        blockReadBytes: UInt64? = nil,
        blockWriteBytes: UInt64? = nil,
        numProcesses: UInt64? = nil
    ) {
        self.id = id
        self.cpuUsageUsec = cpuUsageUsec
        self.memoryUsageBytes = memoryUsageBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.networkRxBytes = networkRxBytes
        self.networkTxBytes = networkTxBytes
        self.blockReadBytes = blockReadBytes
        self.blockWriteBytes = blockWriteBytes
        self.numProcesses = numProcesses
    }
}
