//
//  ArchitectureGuardTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Encodes the milestone's hard architectural constraints as runnable tests:
//    * UI must not import any Backend module (no UI -> Backend edge).
//    * Domain must not import UI (no Domain -> UI edge).
//    * Domain must not use Foundation.Process.
//  This mirrors Scripts/check-architecture.sh, but runs as part of `swift test`.

import Foundation
import XCTest

final class ArchitectureGuardTests: XCTestCase {
    func testUIDoesNotImportAnyBackendModule() throws {
        for file in try swiftFiles(inModule: "CapsuleUI") {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                source.contains("import CapsuleBackend"),
                "CapsuleUI must not import CapsuleBackend (\(file.lastPathComponent))"
            )
            XCTAssertFalse(
                source.contains("import CapsuleCLIBackend"),
                "CapsuleUI must not import CapsuleCLIBackend (\(file.lastPathComponent))"
            )
        }
    }

    func testDomainDoesNotImportUI() throws {
        for file in try swiftFiles(inModule: "CapsuleDomain") {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                source.contains("import CapsuleUI"),
                "CapsuleDomain must not import CapsuleUI (\(file.lastPathComponent))"
            )
        }
    }

    func testDomainDoesNotUseProcess() throws {
        for file in try swiftFiles(inModule: "CapsuleDomain") {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                source.contains("Process("),
                "CapsuleDomain must not use Foundation.Process (\(file.lastPathComponent))"
            )
        }
    }

    func testUIDoesNotImportTerminalEngine() throws {
        for file in try swiftFiles(inModule: "CapsuleUI") {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                source.contains("import CapsuleTerminal"),
                "CapsuleUI must not import CapsuleTerminal (\(file.lastPathComponent))"
            )
        }
    }

    func testDomainDoesNotImportTerminalEngine() throws {
        for file in try swiftFiles(inModule: "CapsuleDomain") {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                source.contains("import CapsuleTerminal"),
                "CapsuleDomain must not import CapsuleTerminal (\(file.lastPathComponent))"
            )
        }
    }

    func testTerminalEngineDoesNotImportBackendModules() throws {
        for file in try swiftFiles(inModule: "CapsuleTerminal") {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                source.contains("import CapsuleBackend"),
                "CapsuleTerminal must not import CapsuleBackend (\(file.lastPathComponent))"
            )
            XCTAssertFalse(
                source.contains("import CapsuleCLIBackend"),
                "CapsuleTerminal must not import CapsuleCLIBackend (\(file.lastPathComponent))"
            )
        }
    }

    func testGuardActuallyFoundSources() throws {
        // Guards the guard: if path resolution breaks, the loops above would pass
        // vacuously. Make sure we are really scanning files.
        XCTAssertFalse(try swiftFiles(inModule: "CapsuleUI").isEmpty)
        XCTAssertFalse(try swiftFiles(inModule: "CapsuleDomain").isEmpty)
        XCTAssertFalse(try swiftFiles(inModule: "CapsuleTerminal").isEmpty)
    }

    // MARK: - Helpers

    private func sourcesRoot() -> URL {
        // .../Tests/CapsuleUnitTests/ArchitectureGuardTests.swift -> package root -> Sources
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    private func swiftFiles(inModule module: String) throws -> [URL] {
        let directory = sourcesRoot().appendingPathComponent(module)
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }
}
