//
//  BuildConfiguration.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  A typed description of a `container build` invocation; `arguments` is the single source of
//  truth for its argv. A tag is required at the model layer (the CLI's default `--tag` is a
//  random UUID, which would orphan the image). Flags mirror `container build` v1.0.0.

import Foundation

public struct BuildConfiguration: Sendable, Equatable {
    public var contextDirectory: URL
    public var tag: String
    /// Path to a Dockerfile/Containerfile (`-f`); nil uses the context default.
    public var dockerfile: String?
    /// Build-time variables as `KEY=value` tokens (`--build-arg`).
    public var buildArgs: [String]
    public var noCache: Bool
    /// When true, requests `--progress plain` — the "plain progress" retry that keeps raw,
    /// uncollapsed build output for diagnosis.
    public var plainProgress: Bool

    public init(
        contextDirectory: URL,
        tag: String,
        dockerfile: String? = nil,
        buildArgs: [String] = [],
        noCache: Bool = false,
        plainProgress: Bool = false
    ) {
        self.contextDirectory = contextDirectory
        self.tag = tag
        self.dockerfile = dockerfile
        self.buildArgs = buildArgs
        self.noCache = noCache
        self.plainProgress = plainProgress
    }

    /// The argv after `container`: `build` flags then the context directory (positional last).
    public var arguments: [String] {
        var argv = ["build", "--tag", tag]
        if let dockerfile { argv += ["--file", dockerfile] }
        for value in buildArgs { argv += ["--build-arg", value] }
        if noCache { argv.append("--no-cache") }
        if plainProgress { argv += ["--progress", "plain"] }
        argv.append(contextDirectory.path)
        return argv
    }
}
