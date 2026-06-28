//
//  CLIProcessRunner.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The one place in Capsule that spawns `Foundation.Process`. The domain and UI layers
//  are forbidden from importing `Process` (enforced by the architecture guard); they
//  reach the CLI only through the backend port, which this adapter satisfies.

import CapsuleBackend
import Foundation

/// A thin async wrapper around `Foundation.Process` that runs a CLI invocation off the
/// main actor, capturing stdout and stderr through independent pipes.
public struct CLIProcessRunner: Sendable {
    /// Location of the executable to spawn (e.g. `/usr/local/bin/container`).
    public let executableURL: URL

    public init(executableURL: URL) {
        self.executableURL = executableURL
    }

    /// Runs the executable to completion and returns its buffered output.
    ///
    /// `environment` is merged *over* the current process environment, so callers can
    /// override or add variables without dropping `PATH`, `HOME`, etc. stdout and stderr
    /// are drained concurrently so a chatty stream on one pipe cannot deadlock the other.
    public func run(
        _ arguments: [String],
        environment: [String: String] = [:],
        standardInput: String? = nil
    ) async throws -> CommandResult {
        let process = makeProcess(arguments: arguments, environment: environment)
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // A secret-bearing input (e.g. a registry password for `--password-stdin`) is fed
        // through stdin so it never appears on argv. The pipe is closed after writing so the
        // child sees EOF and proceeds.
        let inPipe: Pipe? = standardInput == nil ? nil : Pipe()
        process.standardInput = inPipe ?? FileHandle.nullDevice

        // Propagate Swift task cancellation to the spawned child so a cancelled caller
        // (e.g. a stats poll whose stream was torn down) doesn't wait for a long-running
        // command to finish. terminate() fires the terminationHandler, which resolves the
        // continuation with the (signal) result.
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let collector = BufferCollector { continuation.resume(returning: $0) }
                process.terminationHandler = { collector.set(exitCode: $0.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    continuation.resume(
                        throwing: BackendError.executableNotFound(executableURL.path))
                    return
                }
                if let standardInput, let inPipe {
                    let handle = inPipe.fileHandleForWriting
                    handle.write(Data(standardInput.utf8))
                    try? handle.close()
                }
                // Drain both pipes concurrently on background queues.
                DispatchQueue.global().async {
                    collector.set(stdout: outPipe.fileHandleForReading.readDataToEndOfFile())
                }
                DispatchQueue.global().async {
                    collector.set(stderr: errPipe.fileHandleForReading.readDataToEndOfFile())
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Runs the executable and surfaces its output line-by-line as it is produced,
    /// rather than buffering until exit. The stream finishes when the process exits 0,
    /// or finishes throwing ``BackendError/nonZeroExit(command:code:stderr:)`` otherwise.
    /// Breaking out of the consuming loop terminates the underlying process.
    public func stream(
        _ arguments: [String],
        environment: [String: String] = [:]
    ) -> AsyncThrowingStream<OutputLine, Error> {
        AsyncThrowingStream { continuation in
            let process = makeProcess(arguments: arguments, environment: environment)
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let command = ([executableURL.lastPathComponent] + arguments).joined(separator: " ")
            let streamer = LineStreamer(continuation: continuation, command: command)

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    streamer.eof(.stdout)
                } else {
                    streamer.ingest(data, from: .stdout)
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    streamer.eof(.stderr)
                } else {
                    streamer.ingest(data, from: .stderr)
                }
            }
            process.terminationHandler = { streamer.terminated(exitCode: $0.terminationStatus) }

            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: BackendError.executableNotFound(executableURL.path))
            }
        }
    }

    func makeProcess(arguments: [String], environment: [String: String]) -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        var merged = ProcessInfo.processInfo.environment
        for (key, value) in environment { merged[key] = value }
        process.environment = merged
        return process
    }
}

/// Splits incremental pipe data into whole lines and feeds them to a stream
/// continuation. Holds a per-source residual buffer for partial lines that span reads,
/// and finishes the stream once both pipes hit EOF and the process has terminated.
private final class LineStreamer: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncThrowingStream<OutputLine, Error>.Continuation
    private let command: String
    private var residual: [OutputLine.Source: String] = [.stdout: "", .stderr: ""]
    private var eofReached: Set<OutputLine.Source> = []
    private var exitCode: Int32?
    private var stderrText = ""
    private var finished = false

    init(
        continuation: AsyncThrowingStream<OutputLine, Error>.Continuation,
        command: String
    ) {
        self.continuation = continuation
        self.command = command
    }

    func ingest(_ data: Data, from source: OutputLine.Source) {
        lock.lock()
        defer { lock.unlock() }
        var parts = ((residual[source] ?? "") + String(decoding: data, as: UTF8.self))
            .components(separatedBy: "\n")
        residual[source] = parts.removeLast()  // trailing partial line, if any
        for line in parts { emit(source: source, text: line) }
    }

    func eof(_ source: OutputLine.Source) {
        lock.lock()
        defer { lock.unlock() }
        if let remainder = residual[source], !remainder.isEmpty {
            emit(source: source, text: remainder)
            residual[source] = ""
        }
        eofReached.insert(source)
        finishIfReady()
    }

    func terminated(exitCode code: Int32) {
        lock.lock()
        defer { lock.unlock() }
        exitCode = code
        finishIfReady()
    }

    /// Caller holds `lock`.
    private func emit(source: OutputLine.Source, text: String) {
        continuation.yield(OutputLine(source: source, text: text))
        if source == .stderr {
            stderrText += stderrText.isEmpty ? text : "\n" + text
        }
    }

    /// Caller holds `lock`.
    private func finishIfReady() {
        guard !finished,
            let code = exitCode,
            eofReached.contains(.stdout),
            eofReached.contains(.stderr)
        else { return }
        finished = true
        if code == 0 {
            continuation.finish()
        } else {
            continuation.finish(
                throwing: BackendError.nonZeroExit(command: command, code: code, stderr: stderrText)
            )
        }
    }
}

/// Collects the three independent completion signals of a process run — stdout EOF,
/// stderr EOF, and termination — and fires `onComplete` exactly once, when all three
/// have arrived (in any order).
private final class BufferCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout: Data?
    private var stderr: Data?
    private var exitCode: Int32?
    private let onComplete: (CommandResult) -> Void

    init(onComplete: @escaping (CommandResult) -> Void) {
        self.onComplete = onComplete
    }

    func set(stdout data: Data) { mutate { $0.stdout = data } }
    func set(stderr data: Data) { mutate { $0.stderr = data } }
    func set(exitCode code: Int32) { mutate { $0.exitCode = code } }

    private func mutate(_ body: (BufferCollector) -> Void) {
        lock.lock()
        body(self)
        let finished: CommandResult?
        if let stdout, let stderr, let exitCode {
            finished = CommandResult(
                exitCode: exitCode,
                stdout: String(decoding: stdout, as: UTF8.self),
                stderr: String(decoding: stderr, as: UTF8.self)
            )
        } else {
            finished = nil
        }
        lock.unlock()
        if let finished { onComplete(finished) }
    }
}
