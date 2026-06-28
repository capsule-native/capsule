//
//  CLIContainerBackend.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The `ContainerBackend` adapter backed by the `container` CLI. It owns no parsing or
//  process logic of its own: it composes the typed ``CLICommand`` argv, runs it through
//  a ``ProcessRunning`` seam, and decodes via ``OutputParser``. Every typed command maps
//  a non-zero exit to ``BackendError/nonZeroExit(command:code:stderr:)``.

import CapsuleBackend
import CapsuleDiagnostics
import Foundation

public struct CLIContainerBackend: ContainerBackend {
    /// Location of the backing CLI executable.
    public let executableURL: URL

    private let runner: any ProcessRunning

    /// Production initializer: resolves the executable (explicit path → well-known
    /// locations → `PATH`) and drives it with a real ``CLIProcessRunner``.
    public init(executableURL: URL = URL(fileURLWithPath: "/usr/local/bin/container")) {
        let resolved = ExecutableLocator.resolve(explicitPath: executableURL.path) ?? executableURL
        self.executableURL = resolved
        self.runner = CLIProcessRunner(executableURL: resolved)
    }

    /// Testing/seam initializer: inject any ``ProcessRunning``.
    init(executableURL: URL, runner: any ProcessRunning) {
        self.executableURL = executableURL
        self.runner = runner
    }

    // MARK: - System & capabilities

    public func version() async throws -> BackendVersion {
        let output = try await runChecked(CLICommand.version())
        return try OutputParser.parseVersion(Data(output.stdout.utf8))
    }

    public func capabilities() async throws -> BackendCapabilities {
        BackendCapabilities.derive(from: try await version())
    }

    public func systemStatus() async throws -> SystemRunState {
        // Deliberately not `runChecked`: a *stopped* service often exits non-zero, which
        // is a valid answer rather than an error. A genuinely unreachable service (a
        // spawn / XPC failure) makes `runner.run` itself throw, which we let propagate so
        // the domain can normalize it to `.daemonUnavailable`.
        Log.backend.debug("container system status")
        let result = try await runner.run(CLICommand.systemStatus(), environment: [:])
        return SystemStatusParser.parse(stdout: result.stdout, stderr: result.stderr)
    }

    public func startSystem() async throws {
        _ = try await runChecked(CLICommand.startSystem())
    }

    public func stopSystem() async throws {
        _ = try await runChecked(CLICommand.stopSystem())
    }

    // MARK: - Containers

    public func listContainers(all: Bool = false) async throws -> [ContainerSummary] {
        let output = try await runChecked(CLICommand.listContainers(all: all))
        return try OutputParser.parseContainers(Data(output.stdout.utf8))
    }

    public func inspectContainer(id: String) async throws -> Parsed<ContainerSummary> {
        let output = try await runChecked(CLICommand.inspectContainer(id: id))
        let value = (try? OutputParser.parseContainers(Data(output.stdout.utf8)))?.first
        return Parsed(value: value, raw: output.stdout)
    }

    public func startContainer(id: String) async throws {
        _ = try await runChecked(CLICommand.startContainer(id: id))
    }

    public func stopContainer(id: String, options: StopOptions) async throws {
        _ = try await runChecked(CLICommand.stopContainer(id: id, options: options))
    }

    public func containerStats(ids: [String]) async throws -> [ContainerStatsSample] {
        let output = try await runChecked(CLICommand.containerStats(ids: ids))
        return try OutputParser.parseStats(Data(output.stdout.utf8))
    }

    public func streamContainerStats(
        ids: [String], interval: Duration
    )
        -> AsyncThrowingStream<[ContainerStatsSample], Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        let batch = try await containerStats(ids: ids)
                        if Task.isCancelled { break }
                        continuation.yield(batch)
                        try await Task.sleep(for: interval)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func removeContainer(id: String, force: Bool) async throws {
        _ = try await runChecked(CLICommand.removeContainer(id: id, force: force))
    }

    public func killContainer(id: String, signal: String?) async throws {
        _ = try await runChecked(CLICommand.killContainer(id: id, signal: signal))
    }

    public func pruneContainers() async throws -> PruneResult {
        // prune exits 0 on success and prints a human "Reclaimed …" line; do not treat a
        // non-empty stderr as failure — only a non-zero exit is a real error.
        let result = try await runner.run(CLICommand.pruneContainers(), environment: [:])
        guard result.isSuccess else {
            throw BackendError.nonZeroExit(
                command: "container prune", code: result.exitCode, stderr: result.stderr)
        }
        return OutputParser.parsePruneResult(stdout: result.stdout, stderr: result.stderr)
    }

    public func exportContainer(id: String, to url: URL) async throws {
        _ = try await runChecked(CLICommand.exportContainer(id: id, to: url))
    }

    public func followLogs(container id: String) -> AsyncThrowingStream<OutputLine, Error> {
        runner.stream(CLICommand.followLogs(container: id), environment: [:])
    }

    public func fetchLogs(container id: String, tail: Int?, boot: Bool) async throws -> [OutputLine]
    {
        let output = try await runChecked(
            CLICommand.fetchLogs(container: id, tail: tail, boot: boot))
        // Drop the trailing newline so a normal `…\n`-terminated snapshot doesn't yield a
        // spurious blank final line in the pane or the saved transcript.
        let text = output.stdout.hasSuffix("\n") ? String(output.stdout.dropLast()) : output.stdout
        guard !text.isEmpty else { return [] }
        return
            text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { OutputLine(source: .stdout, text: String($0)) }
    }

    public func runContainer(_ config: RunConfiguration) async throws -> String {
        // apple/container prints the new container id on stdout for a detached run; take the
        // last non-empty line as the id (any progress lines precede it).
        let output = try await runChecked(CLICommand.run(config))
        let id =
            output.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .last
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return id
    }

    public func copyToContainer(
        source: URL, containerID: String, containerPath: String
    ) async throws {
        _ = try await runChecked(
            CLICommand.copy(source: source.path, destination: "\(containerID):\(containerPath)"))
    }

    public func copyFromContainer(
        containerID: String, containerPath: String, destination: URL
    ) async throws {
        _ = try await runChecked(
            CLICommand.copy(
                source: "\(containerID):\(containerPath)", destination: destination.path))
    }

    public func listContainerDirectory(
        id: String, path: String
    ) async throws -> [ContainerFileEntry] {
        // Use the non-throwing escape hatch so a non-zero exit (no such path / no `ls` / not
        // running) surfaces a typed error the domain can degrade gracefully on, with the raw
        // stderr preserved for diagnosis.
        let output = try await runRaw(CLICommand.listDirectory(id: id, path: path))
        guard output.exitCode == 0 else {
            throw BackendError.nonZeroExit(
                command: commandDescription(CLICommand.listDirectory(id: id, path: path)),
                code: output.exitCode, stderr: output.stderr)
        }
        return OutputParser.parseDirectoryListing(output.stdout)
    }

    // MARK: - Images

    public func listImages() async throws -> [ImageSummary] {
        let output = try await runChecked(CLICommand.listImages())
        return try OutputParser.parseImages(Data(output.stdout.utf8))
    }

    public func inspectImage(reference: String) async throws -> Parsed<ImageSummary> {
        let output = try await runChecked(CLICommand.inspectImage(reference: reference))
        let value = (try? OutputParser.parseImages(Data(output.stdout.utf8)))?.first
        return Parsed(value: value, raw: output.stdout)
    }

    public func removeImage(reference: String) async throws {
        _ = try await runChecked(CLICommand.removeImage(reference: reference))
    }

    public func pullImage(
        reference: String, platform: String?
    ) -> AsyncThrowingStream<OutputLine, Error> {
        runner.stream(
            CLICommand.pullImage(reference: reference, platform: platform), environment: [:])
    }

    public func pushImage(
        reference: String, platform: String?
    ) -> AsyncThrowingStream<OutputLine, Error> {
        runner.stream(
            CLICommand.pushImage(reference: reference, platform: platform), environment: [:])
    }

    public func buildImage(_ config: BuildConfiguration) -> AsyncThrowingStream<OutputLine, Error> {
        runner.stream(CLICommand.build(config), environment: [:])
    }

    public func saveImage(references: [String], to url: URL, platform: String?) async throws {
        _ = try await runChecked(
            CLICommand.saveImage(references: references, to: url, platform: platform))
    }

    public func loadImage(from url: URL) async throws {
        _ = try await runChecked(CLICommand.loadImage(from: url))
    }

    public func tagImage(source: String, target: String) async throws {
        _ = try await runChecked(CLICommand.tagImage(source: source, target: target))
    }

    public func pruneImages(all: Bool) async throws -> PruneResult {
        // Like `pruneContainers`: prune exits 0 and prints a human "Reclaimed …" line, so a
        // non-empty stderr is not a failure — only a non-zero exit is a real error.
        let result = try await runner.run(CLICommand.pruneImages(all: all), environment: [:])
        guard result.isSuccess else {
            throw BackendError.nonZeroExit(
                command: "container image prune", code: result.exitCode, stderr: result.stderr)
        }
        return OutputParser.parsePruneResult(stdout: result.stdout, stderr: result.stderr)
    }

    // MARK: - Volumes / networks / registries / machines / builder

    public func listVolumes() async throws -> [VolumeSummary] {
        let output = try await runChecked(CLICommand.listVolumes())
        return try OutputParser.parseVolumes(Data(output.stdout.utf8))
    }

    public func listNetworks() async throws -> [NetworkSummary] {
        let output = try await runChecked(CLICommand.listNetworks())
        return try OutputParser.parseNetworks(Data(output.stdout.utf8))
    }

    public func listRegistries() async throws -> [RegistrySummary] {
        let output = try await runChecked(CLICommand.listRegistries())
        return try OutputParser.parseRegistries(Data(output.stdout.utf8))
    }

    public func registryLogin(server: String, username: String?, password: String?) async throws {
        try await runLogin(server: server, username: username, password: password)
    }

    public func registryLogout(server: String) async throws {
        _ = try await runChecked(CLICommand.registryLogout(server: server))
    }

    public func registryTest(server: String, username: String?, password: String?) async throws {
        // apple/container has no dry-run verb; a real login validates the credentials.
        try await runLogin(server: server, username: username, password: password)
    }

    /// Runs `registry login`, feeding the password through stdin (`--password-stdin`). The
    /// password is never placed on argv, so it cannot leak via `ps`, the debug log line, or
    /// the error's `command:` field. Only the argv (sans secret) is logged.
    private func runLogin(server: String, username: String?, password: String?) async throws {
        let argv = CLICommand.registryLogin(server: server, username: username)
        Log.backend.debug("container \(argv.joined(separator: " "), privacy: .public)")
        let result = try await runner.run(argv, environment: [:], standardInput: password ?? "")
        guard result.isSuccess else {
            throw BackendError.nonZeroExit(
                command: commandDescription(argv), code: result.exitCode, stderr: result.stderr)
        }
    }

    public func listMachines() async throws -> [MachineSummary] {
        let output = try await runChecked(CLICommand.listMachines())
        return try OutputParser.parseMachines(Data(output.stdout.utf8))
    }

    public func builderStatus() async throws -> BuilderStatus {
        let output = try await runChecked(CLICommand.builderStatus())
        return try OutputParser.parseBuilderStatus(Data(output.stdout.utf8))
    }

    // MARK: - Escape hatches

    public func runRaw(_ arguments: [String]) async throws -> RawCommandOutput {
        let result = try await runner.run(arguments, environment: [:])
        return RawCommandOutput(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }

    public func streamRaw(_ arguments: [String]) -> AsyncThrowingStream<OutputLine, Error> {
        runner.stream(arguments, environment: [:])
    }

    // MARK: - Helpers

    /// Runs an argument vector and throws a typed error when the CLI exits non-zero.
    private func runChecked(_ arguments: [String]) async throws -> CommandResult {
        Log.backend.debug("container \(arguments.joined(separator: " "), privacy: .public)")
        let result = try await runner.run(arguments, environment: [:])
        guard result.isSuccess else {
            throw BackendError.nonZeroExit(
                command: commandDescription(arguments),
                code: result.exitCode,
                stderr: result.stderr
            )
        }
        return result
    }

    private func commandDescription(_ arguments: [String]) -> String {
        ([executableURL.lastPathComponent] + arguments).joined(separator: " ")
    }
}
