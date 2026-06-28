//
//  CLICommand.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Typed factory for `container` argument vectors. This is the *only* place argv is
//  assembled from typed inputs, so callers (the backend, and ultimately views) never
//  hand-concatenate CLI strings. Each vector omits the executable itself — the runner
//  owns `executableURL` — and prefers canonical subcommand names over their aliases.
//
//  Subcommand names and flags mirror `container` v1.0.0, verified against `--help`.

import CapsuleBackend
import Foundation

public enum CLICommand {
    // MARK: - System

    public static func version() -> [String] {
        ArgumentBuilder("system", "version").flag("--format", "json").arguments
    }

    public static func systemStatus() -> [String] {
        ArgumentBuilder("system", "status").arguments
    }

    public static func startSystem() -> [String] {
        ArgumentBuilder("system", "start").arguments
    }

    public static func stopSystem() -> [String] {
        ArgumentBuilder("system", "stop").arguments
    }

    // MARK: - Containers

    public static func listContainers(all: Bool) -> [String] {
        ArgumentBuilder("list").option("--all", enabled: all).flag("--format", "json").arguments
    }

    public static func inspectContainer(id: String) -> [String] {
        // `container inspect` does not accept `--format`; it emits JSON by default.
        ArgumentBuilder("inspect").adding(id).arguments
    }

    public static func startContainer(id: String) -> [String] {
        ArgumentBuilder("start").adding(id).arguments
    }

    public static func stopContainer(id: String, options: StopOptions) -> [String] {
        ArgumentBuilder("stop")
            .flag("--time", options.timeout.map(String.init))
            .flag("--signal", options.signal)
            .adding(id)
            .arguments
    }

    public static func containerStats(ids: [String]) -> [String] {
        ArgumentBuilder("stats")
            .option("--no-stream", enabled: true)
            .flag("--format", "json")
            .adding(contentsOf: ids)
            .arguments
    }

    public static func removeContainer(id: String, force: Bool) -> [String] {
        ArgumentBuilder("delete").option("--force", enabled: force).adding(id).arguments
    }

    public static func killContainer(id: String, signal: String?) -> [String] {
        ArgumentBuilder("kill").flag("--signal", signal).adding(id).arguments
    }

    public static func pruneContainers() -> [String] {
        ArgumentBuilder("prune").arguments
    }

    public static func exportContainer(id: String, to url: URL) -> [String] {
        ArgumentBuilder("export").flag("--output", url.path).adding(id).arguments
    }

    public static func followLogs(container id: String) -> [String] {
        ArgumentBuilder("logs").option("--follow", enabled: true).adding(id).arguments
    }

    public static func fetchLogs(container id: String, tail: Int?, boot: Bool) -> [String] {
        ArgumentBuilder("logs")
            .option("--boot", enabled: boot)
            .flag("-n", tail.map(String.init))
            .adding(id)
            .arguments
    }

    /// Detached/interactive run argv comes straight from the typed configuration, the single
    /// source of truth shared with the domain's terminal-request builder.
    public static func run(_ config: RunConfiguration) -> [String] {
        config.arguments
    }

    /// Canonical `copy` subcommand (not the `cp` alias). Endpoints are `container:path` or a
    /// local path, already composed by the caller.
    public static func copy(source: String, destination: String) -> [String] {
        ArgumentBuilder("copy").adding(source, destination).arguments
    }

    /// Lists a directory inside a running container; apple/container has no file-listing verb,
    /// so we exec `ls -la` and parse it leniently.
    public static func listDirectory(id: String, path: String) -> [String] {
        ArgumentBuilder("exec").adding(id, "ls", "-la", path).arguments
    }

    // MARK: - Images

    public static func build(_ config: BuildConfiguration) -> [String] {
        config.arguments
    }

    public static func listImages() -> [String] {
        ArgumentBuilder("image", "list").flag("--format", "json").arguments
    }

    public static func inspectImage(reference: String) -> [String] {
        // `container image inspect` does not accept `--format`; it emits JSON by default.
        ArgumentBuilder("image", "inspect").adding(reference).arguments
    }

    public static func pullImage(reference: String, platform: String?) -> [String] {
        ArgumentBuilder("image", "pull").flag("--platform", platform).adding(reference).arguments
    }

    public static func pushImage(reference: String, platform: String?) -> [String] {
        ArgumentBuilder("image", "push").flag("--platform", platform).adding(reference).arguments
    }

    public static func saveImage(references: [String], to url: URL, platform: String?) -> [String] {
        ArgumentBuilder("image", "save")
            .flag("--output", url.path)
            .flag("--platform", platform)
            .adding(contentsOf: references)
            .arguments
    }

    public static func loadImage(from url: URL) -> [String] {
        ArgumentBuilder("image", "load").flag("--input", url.path).arguments
    }

    public static func tagImage(source: String, target: String) -> [String] {
        ArgumentBuilder("image", "tag").adding(source, target).arguments
    }

    public static func pruneImages(all: Bool) -> [String] {
        ArgumentBuilder("image", "prune").option("--all", enabled: all).arguments
    }

    public static func removeImage(reference: String) -> [String] {
        ArgumentBuilder("image", "delete").adding(reference).arguments
    }

    // MARK: - Volumes / networks / registries / machines / builder

    public static func listVolumes() -> [String] {
        ArgumentBuilder("volume", "list").flag("--format", "json").arguments
    }

    public static func listNetworks() -> [String] {
        ArgumentBuilder("network", "list").flag("--format", "json").arguments
    }

    public static func listRegistries() -> [String] {
        ArgumentBuilder("registry", "list").flag("--format", "json").arguments
    }

    /// The login argv carries `--password-stdin` and (optionally) the username, but never
    /// the password itself — the secret is written to the child's stdin so it cannot leak
    /// via `ps`, the debug log, an error's `command:` field, or any task transcript.
    public static func registryLogin(server: String, username: String?) -> [String] {
        ArgumentBuilder("registry", "login")
            .flag("--username", username)
            .option("--password-stdin", enabled: true)
            .adding(server)
            .arguments
    }

    public static func registryLogout(server: String) -> [String] {
        ArgumentBuilder("registry", "logout").adding(server).arguments
    }

    public static func listMachines() -> [String] {
        ArgumentBuilder("machine", "list").flag("--format", "json").arguments
    }

    public static func builderStatus() -> [String] {
        ArgumentBuilder("builder", "status").flag("--format", "json").arguments
    }
}
