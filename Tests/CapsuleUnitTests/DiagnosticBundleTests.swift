//
//  DiagnosticBundleTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation
import XCTest

@testable import CapsuleDiagnostics

final class DiagnosticBundleTests: XCTestCase {
    // MARK: - Log categories

    func testLogExposesPerSubsystemCategories() {
        let names = Set(LogCategory.allCases.map(\.rawValue))
        XCTAssertTrue(names.isSuperset(of: ["backend", "ui", "tasks"]))
    }

    func testLogSubsystem() {
        XCTAssertEqual(Log.subsystem, "com.capsule.app")
    }

    // MARK: - Options defaults

    func testDefaultOptionsAreLocalAndContentFree() {
        let options = DiagnosticOptions.default
        XCTAssertFalse(options.includeCommandContent, "command content must be opt-in")
        XCTAssertFalse(options.allowSubmission, "submission must be opt-in; local-only by default")
    }

    // MARK: - Bundle assembly

    private func makeBuilder() -> DiagnosticBundleBuilder {
        DiagnosticBundleBuilder(
            capsuleVersion: "1.2.3",
            containerSystemVersion: "container CLI 1.0.0",
            hostOSVersion: "macOS 26.0",
            logEntries: ["backend: started", "tasks: refresh"],
            transcript: [
                CommandTranscriptEntry(
                    command: ["container", "registry", "login", "--password", "hunter2"],
                    exitCode: 1,
                    stderr: "auth failed for --password hunter2"
                )
            ]
        )
    }

    func testBundleCarriesVersionHostAndLogFields() {
        let bundle = makeBuilder().build()
        XCTAssertEqual(bundle.capsuleVersion, "1.2.3")
        XCTAssertEqual(bundle.containerSystemVersion, "container CLI 1.0.0")
        XCTAssertEqual(bundle.hostOSVersion, "macOS 26.0")
        XCTAssertEqual(bundle.logEntries, ["backend: started", "tasks: refresh"])
    }

    func testLogEntriesAreSecretScrubbed() {
        // A credential that leaks into a log line must not survive into an exported bundle —
        // logs are always scrubbed, independent of the command-content opt-in.
        let builder = DiagnosticBundleBuilder(
            capsuleVersion: "1.2.3",
            containerSystemVersion: nil,
            hostOSVersion: "macOS 26.0",
            logEntries: ["registry login --password hunter2", "header: Bearer sk-live-abcdef"],
            transcript: []
        )
        let joined = builder.build().logEntries.joined(separator: "\n")
        XCTAssertFalse(joined.contains("hunter2"), "a password in a log line must be scrubbed")
        XCTAssertFalse(
            joined.contains("sk-live-abcdef"), "a bearer token in a log line must be scrubbed")
    }

    func testCommandContentIsRedactedByDefault() {
        let bundle = makeBuilder().build()  // default options: content off
        XCTAssertFalse(bundle.includesCommandContent)

        let entry = bundle.commandTranscript[0]
        // Exit code (a fact, not content) is retained...
        XCTAssertEqual(entry.exitCode, 1)
        // ...but the argv and stderr content are gone.
        XCTAssertFalse(entry.command.joined(separator: " ").contains("hunter2"))
        XCTAssertFalse(entry.command.joined(separator: " ").contains("registry"))
        XCTAssertFalse(entry.stderr.contains("hunter2"))
    }

    func testOptedInContentIsCapturedButSecretsStillScrubbed() {
        let bundle = makeBuilder().build(options: DiagnosticOptions(includeCommandContent: true))
        XCTAssertTrue(bundle.includesCommandContent)

        let entry = bundle.commandTranscript[0]
        // The command is now visible...
        XCTAssertTrue(entry.command.contains("registry"))
        XCTAssertTrue(entry.command.contains("login"))
        // ...but the password is never present, even when content is opted in.
        XCTAssertFalse(entry.command.contains("hunter2"))
        XCTAssertEqual(
            entry.command,
            [
                "container", "registry", "login", "--password", SecretRedactor.placeholder,
            ])
        XCTAssertFalse(entry.stderr.contains("hunter2"))
    }

    // MARK: - Export

    func testExportedJSONContainsRequiredFields() throws {
        let json = try makeBuilder().build().exportedJSON()
        let text = try XCTUnwrap(String(data: json, encoding: .utf8))
        XCTAssertTrue(text.contains("1.2.3"))
        XCTAssertTrue(text.contains("container CLI 1.0.0"))
        XCTAssertTrue(text.contains("macOS 26.0"))
        XCTAssertTrue(text.contains("backend: started"))
    }

    func testExportedJSONRoundTrips() throws {
        let bundle = makeBuilder().build()
        let json = try bundle.exportedJSON()
        let decoded = try JSONDecoder().decode(DiagnosticBundle.self, from: json)
        XCTAssertEqual(decoded, bundle)
    }

    func testWriteToDirectoryCreatesReadableFile() throws {
        let bundle = makeBuilder().build()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capsule-diag-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try bundle.write(to: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(DiagnosticBundle.self, from: data)
        XCTAssertEqual(decoded, bundle)
    }
}
