//
//  ProcessRunning.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The seam between `CLIContainerBackend` and the process layer. Production wires the
//  real `CLIProcessRunner`; tests substitute a stub so the adapter's argv building,
//  decoding, and error mapping are verified without spawning anything.

import CapsuleBackend
import Foundation

protocol ProcessRunning: Sendable {
    func run(_ arguments: [String], environment: [String: String]) async throws -> CommandResult
    func stream(
        _ arguments: [String],
        environment: [String: String]
    ) -> AsyncThrowingStream<OutputLine, Error>
}

extension CLIProcessRunner: ProcessRunning {}
