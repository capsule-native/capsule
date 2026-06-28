//
//  StubProcessRunner.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  A `ProcessRunning` test double that returns canned output and records the argument
//  vectors it was asked to run, so `CLIContainerBackend` can be exercised end-to-end
//  (argv building → decoding → error mapping) without ever spawning a real process.

import CapsuleBackend
import Foundation

@testable import CapsuleCLIBackend

final class StubProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()

    /// Buffered result returned by `run` (overridden by `resultProvider` when set).
    var result = CommandResult(exitCode: 0, stdout: "", stderr: "")
    /// Optional per-invocation result, keyed off the argument vector.
    var resultProvider: (@Sendable ([String]) -> CommandResult)?
    /// Lines yielded by `stream`, followed by a normal/throwing finish per `streamExit`.
    var streamLines: [OutputLine] = []
    var streamExit: Int32 = 0

    private var calls: [[String]] = []

    var lastCall: [String]? {
        withLock { calls.last }
    }

    func run(_ arguments: [String], environment: [String: String]) async throws -> CommandResult {
        let (provider, fixed) = withLock {
            () -> ((@Sendable ([String]) -> CommandResult)?, CommandResult) in
            calls.append(arguments)
            return (resultProvider, result)
        }
        return provider?(arguments) ?? fixed
    }

    func stream(
        _ arguments: [String],
        environment: [String: String]
    ) -> AsyncThrowingStream<OutputLine, Error> {
        let (lines, exit) = withLock { () -> ([OutputLine], Int32) in
            calls.append(arguments)
            return (streamLines, streamExit)
        }
        let command = arguments.joined(separator: " ")
        return AsyncThrowingStream { continuation in
            for line in lines { continuation.yield(line) }
            if exit == 0 {
                continuation.finish()
            } else {
                continuation.finish(
                    throwing: BackendError.nonZeroExit(command: command, code: exit, stderr: "")
                )
            }
        }
    }

    /// Synchronous critical section — keeps `NSLock` out of `async` contexts.
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
