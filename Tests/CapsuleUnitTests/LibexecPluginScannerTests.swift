//
//  LibexecPluginScannerTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import XCTest

@testable import CapsuleApp

final class LibexecPluginScannerTests: XCTestCase {
    private let fm = FileManager.default

    private func makeExecutable(_ url: URL) throws {
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makeNonExecutable(_ url: URL) throws {
        try Data("x".utf8).write(to: url)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }

    func testScansPrefixedExecutablesIgnoringTheRestAndDedupes() throws {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dirA = root.appendingPathComponent("a")
        let dirB = root.appendingPathComponent("b")
        try fm.createDirectory(at: dirA, withIntermediateDirectories: true)
        try fm.createDirectory(at: dirB, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try makeExecutable(dirA.appendingPathComponent("container-buildx"))
        try makeExecutable(dirA.appendingPathComponent("container-compose"))
        try makeExecutable(dirA.appendingPathComponent("helper"))  // no prefix → ignored
        try makeNonExecutable(dirA.appendingPathComponent("container-doc"))  // not exec → ignored
        try fm.createDirectory(  // dir → ignored
            at: dirA.appendingPathComponent("container-dir"),
            withIntermediateDirectories: true)
        try makeExecutable(dirB.appendingPathComponent("container-buildx"))  // dup name → deduped
        try makeExecutable(dirB.appendingPathComponent("container-extra"))

        let scanner = LibexecPluginScanner(directories: [dirA.path, dirB.path])
        let plugins = scanner.installedPlugins()

        XCTAssertEqual(Set(plugins.map(\.name)), ["buildx", "compose", "extra"])
        XCTAssertEqual(plugins.count, 3)
        // First directory wins on a name collision.
        XCTAssertEqual(
            plugins.first { $0.name == "buildx" }?.path,
            dirA.appendingPathComponent("container-buildx").path)
    }

    func testMissingDirectoriesReturnEmptyCleanly() {
        let scanner = LibexecPluginScanner(
            directories: ["/no/such/dir/\(UUID().uuidString)"])
        XCTAssertEqual(scanner.installedPlugins(), [])
    }
}
