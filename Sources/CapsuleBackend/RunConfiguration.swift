//
//  RunConfiguration.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  A typed description of a `container run` invocation. Its `arguments` is the single source
//  of truth for the argv (after the `container` executable): the CLI adapter uses it for a
//  detached run, and the domain reuses it verbatim to build the interactive `TerminalRequest`
//  for `run -it`. Flags mirror `container run` v1.0.0 (verified against `--help`).

import Foundation

public struct RunConfiguration: Sendable, Equatable {
    public var image: String
    /// Init-process arguments placed after the image.
    public var command: [String]
    /// Environment assignments as `KEY=value` tokens.
    public var env: [String]
    /// Port mappings, e.g. `8080:80` or `127.0.0.1:5432:5432/tcp`.
    public var publishPorts: [String]
    /// Volume/bind mounts, e.g. `/host:/container` or `vol:/data:ro`.
    public var volumes: [String]
    public var name: String?
    public var workdir: String?
    public var user: String?
    public var interactive: Bool
    public var tty: Bool
    public var detach: Bool
    public var remove: Bool

    public init(
        image: String,
        name: String? = nil,
        command: [String] = [],
        env: [String] = [],
        publishPorts: [String] = [],
        volumes: [String] = [],
        workdir: String? = nil,
        user: String? = nil,
        interactive: Bool = false,
        tty: Bool = false,
        detach: Bool = false,
        remove: Bool = false
    ) {
        self.image = image
        self.name = name
        self.command = command
        self.env = env
        self.publishPorts = publishPorts
        self.volumes = volumes
        self.workdir = workdir
        self.user = user
        self.interactive = interactive
        self.tty = tty
        self.detach = detach
        self.remove = remove
    }

    /// The argv after `container`: flags, then the image, then the init-process command.
    /// The image must precede its arguments, so flags are emitted first.
    public var arguments: [String] {
        var argv = ["run"]
        if detach { argv.append("-d") }
        if interactive { argv.append("-i") }
        if tty { argv.append("-t") }
        if remove { argv.append("--rm") }
        if let name { argv += ["--name", name] }
        for value in env { argv += ["-e", value] }
        for port in publishPorts { argv += ["-p", port] }
        for volume in volumes { argv += ["-v", volume] }
        if let workdir { argv += ["-w", workdir] }
        if let user { argv += ["-u", user] }
        argv.append(image)
        argv += command
        return argv
    }
}
