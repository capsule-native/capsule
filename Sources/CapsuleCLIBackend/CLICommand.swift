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

    // MARK: - Images

    public static func listImages() -> [String] {
        ArgumentBuilder("image", "list").flag("--format", "json").arguments
    }

    public static func inspectImage(reference: String) -> [String] {
        // `container image inspect` does not accept `--format`; it emits JSON by default.
        ArgumentBuilder("image", "inspect").adding(reference).arguments
    }

    public static func pullImage(reference: String) -> [String] {
        ArgumentBuilder("image", "pull").adding(reference).arguments
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

    public static func listMachines() -> [String] {
        ArgumentBuilder("machine", "list").flag("--format", "json").arguments
    }

    public static func builderStatus() -> [String] {
        ArgumentBuilder("builder", "status").flag("--format", "json").arguments
    }
}
