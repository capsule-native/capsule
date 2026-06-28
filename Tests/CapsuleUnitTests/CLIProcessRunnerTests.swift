//
//  CLIProcessRunnerTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Exercises the real process plumbing against `/bin/sh` — a stand-in for any
//  executable. These prove the runner itself (pipes, exit codes, env merge, streaming)
//  without depending on the `container` binary, keeping the suite hermetic in CI.

import CapsuleBackend
import Foundation
import XCTest

@testable import CapsuleCLIBackend

final class CLIProcessRunnerTests: XCTestCase {
    private let runner = CLIProcessRunner(executableURL: URL(fileURLWithPath: "/bin/sh"))

    func testCapturesStdoutAndZeroExit() async throws {
        let result = try await runner.run(["-c", "printf 'hello world'"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "hello world")
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.isSuccess)
    }

    func testCapturesStderrAndNonZeroExitSeparately() async throws {
        let result = try await runner.run(["-c", "printf 'boom' 1>&2; exit 3"])

        XCTAssertEqual(result.exitCode, 3)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "boom")
        XCTAssertFalse(result.isSuccess)
    }

    func testMergesInjectedEnvironmentOverProcessEnvironment() async throws {
        // HOME is inherited from the process environment; CAPSULE_TEST_VAR is injected.
        let result = try await runner.run(
            ["-c", #"printf "%s:%s" "$CAPSULE_TEST_VAR" "${HOME:+has-home}""#],
            environment: ["CAPSULE_TEST_VAR": "injected"]
        )

        XCTAssertEqual(result.stdout, "injected:has-home")
    }

    // MARK: - Streaming

    func testStreamYieldsEachStdoutLine() async throws {
        var lines: [OutputLine] = []
        for try await line in runner.stream(["-c", "echo line1; echo line2; echo line3"]) {
            lines.append(line)
        }

        XCTAssertEqual(lines.map(\.text), ["line1", "line2", "line3"])
        XCTAssertTrue(lines.allSatisfy { $0.source == .stdout })
    }

    func testStreamDeliversLinesIncrementallyNotBufferedUntilExit() async throws {
        // The second line is gated behind a sleep; if streaming were buffered until exit
        // the first line could not arrive before the sleep elapses.
        let start = Date()
        var firstLineLatency: TimeInterval?
        var count = 0
        for try await _ in runner.stream(["-c", #"printf 'a\n'; sleep 0.4; printf 'b\n'"#]) {
            if firstLineLatency == nil { firstLineLatency = Date().timeIntervalSince(start) }
            count += 1
        }

        XCTAssertEqual(count, 2)
        let latency = try XCTUnwrap(firstLineLatency)
        XCTAssertLessThan(latency, 0.3, "first line should stream before the 0.4s sleep")
    }

    func testStreamSeparatesStderrAndThrowsOnNonZeroExit() async throws {
        var lines: [OutputLine] = []
        do {
            for try await line in runner.stream(["-c", "echo out; echo bad 1>&2; exit 5"]) {
                lines.append(line)
            }
            XCTFail("stream should throw on non-zero exit")
        } catch let BackendError.nonZeroExit(_, code, stderr) {
            XCTAssertEqual(code, 5)
            XCTAssertTrue(stderr.contains("bad"), "stderr was \(stderr)")
        }

        XCTAssertEqual(lines.first { $0.source == .stdout }?.text, "out")
        XCTAssertEqual(lines.first { $0.source == .stderr }?.text, "bad")
    }
}
