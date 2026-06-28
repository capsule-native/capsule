//
//  ExecutableLocator.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Locates the `container` executable so non-standard installs (Homebrew on Apple
//  silicon, a custom prefix, a `PATH` entry) work without configuration. Resolution
//  order: an explicit configured path, then well-known install locations, then a
//  `which`-style scan of `PATH`.

import Foundation

public enum ExecutableLocator {
    /// Well-known install locations, in priority order.
    public static let defaultCandidates = [
        "/usr/local/bin/container",
        "/opt/homebrew/bin/container",
    ]

    private static let executableName = "container"

    /// Pure resolver with injected filesystem/PATH, for testing and reuse.
    static func resolve(
        explicitPath: String?,
        candidates: [String],
        pathDirectories: [String],
        fileExists: (String) -> Bool
    ) -> URL? {
        if let explicitPath, fileExists(explicitPath) {
            return URL(fileURLWithPath: explicitPath)
        }
        if let hit = candidates.first(where: fileExists) {
            return URL(fileURLWithPath: hit)
        }
        for directory in pathDirectories {
            let candidate = directory + "/" + executableName
            if fileExists(candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    /// Resolves against the real filesystem and the process `PATH`.
    public static func resolve(explicitPath: String? = nil) -> URL? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let directories = path.split(separator: ":").map(String.init)
        return resolve(
            explicitPath: explicitPath,
            candidates: defaultCandidates,
            pathDirectories: directories,
            fileExists: { FileManager.default.isExecutableFile(atPath: $0) }
        )
    }
}
