//
//  OutputParser.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Turns raw CLI stdout (`--format json`) into the port's value types.
//
//  Two robustness properties matter here:
//   * Row lists decode *leniently*: a single element that no longer matches the schema
//     is skipped rather than failing the whole list, so one odd container can't blank
//     the table.
//   * Detail decoding pairs the decoded value with the raw payload (`Parsed`), so a
//     schema change degrades to a raw inspector view instead of a crash.

import CapsuleBackend
import Foundation

public enum OutputParser {
    private static let decoder = JSONDecoder()

    // MARK: - Images

    /// Decodes `container image ls --format json` into image rows, skipping any element
    /// whose schema no longer matches.
    public static func parseImages(_ data: Data) throws -> [ImageSummary] {
        try lossyList(data, decode: CLIImageRecord.self).map { record in
            ImageSummary(
                id: record.id,
                reference: record.configuration.name,
                sizeBytes: record.configuration.descriptor.size,
                digest: record.configuration.descriptor.digest,
                createdAt: record.configuration.creationDate
            )
        }
    }

    // MARK: - Container files

    /// Parses `ls -la` output into directory entries. Lenient: skips the `total N` header
    /// and any line that is not an ls long-format row. The mode column's leading character
    /// distinguishes directories (`d`) and symlinks (`l`); size is column 5; the name is
    /// everything after the date columns (so names with spaces survive). `.`/`..` are
    /// dropped; a symlink's `name -> target` keeps just the link name.
    public static func parseDirectoryListing(_ text: String) -> [ContainerFileEntry] {
        var entries: [ContainerFileEntry] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            if line.hasPrefix("total ") { continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(
                String.init)
            guard fields.count >= 9, let first = fields[0].first, "dlbcps-".contains(first) else {
                continue
            }
            var name = fields[8...].joined(separator: " ")
            if first == "l", let arrow = name.range(of: " -> ") {
                name = String(name[..<arrow.lowerBound])
            }
            if name == "." || name == ".." { continue }
            entries.append(
                ContainerFileEntry(
                    name: name, isDirectory: first == "d", size: Int64(fields[4]), mode: fields[0]))
        }
        return entries
    }

    // MARK: - Containers

    /// Decodes `container ls --format json` into container rows, skipping any element
    /// whose schema no longer matches.
    public static func parseContainers(_ data: Data) throws -> [ContainerSummary] {
        try lossyList(data, decode: CLIContainerRecord.self).map { record in
            ContainerSummary(
                id: record.id,
                name: record.configuration.id,
                image: record.configuration.image.reference,
                state: record.status.state,
                ip: record.status.networks.lazy.compactMap(\.ipAddress).first,
                createdAt: record.configuration.creationDate,
                volumeMounts: (record.configuration.mounts ?? []).compactMap(\.volumeName),
                networkNames: (record.configuration.networks ?? []).compactMap(\.network)
            )
        }
    }

    // MARK: - Stats

    /// Decodes `container stats --format json` into samples, skipping any element whose
    /// schema no longer matches (e.g. missing the required `id`).
    public static func parseStats(_ data: Data) throws -> [ContainerStatsSample] {
        try lossyList(data, decode: CLIContainerStatsRecord.self).map { record in
            ContainerStatsSample(
                id: record.id,
                cpuUsageUsec: record.cpuUsageUsec,
                memoryUsageBytes: record.memoryUsageBytes,
                memoryLimitBytes: record.memoryLimitBytes,
                networkRxBytes: record.networkRxBytes,
                networkTxBytes: record.networkTxBytes,
                blockReadBytes: record.blockReadBytes,
                blockWriteBytes: record.blockWriteBytes,
                numProcesses: record.numProcesses
            )
        }
    }

    // MARK: - Prune

    /// Extracts the "Reclaimed … in disk space" line from prune output (stdout or stderr; the
    /// CLI's stream choice is unverified), keeping the full combined text in `raw`.
    public static func parsePruneResult(stdout: String, stderr: String) -> PruneResult {
        let combined = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        let line =
            combined.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first {
                $0.range(of: "Reclaimed", options: .caseInsensitive) != nil
                    && $0.range(of: "disk space", options: .caseInsensitive) != nil
            }
        return PruneResult(reclaimedDescription: line, raw: combined)
    }

    // MARK: - System version

    /// Decodes `container system version --format json` into a `BackendVersion`, pairing
    /// the `container` client entry with the `container-apiserver` server entry.
    public static func parseVersion(_ data: Data) throws -> BackendVersion {
        let components = try lossyList(data, decode: CLIVersionComponent.self)
        let client =
            components.first { $0.appName == "container" }?.version
            ?? components.first?.version
            ?? ""
        let server = components.first { $0.appName.contains("apiserver") }?.version
        return BackendVersion(client: client, server: server)
    }

    public static func parseComponentVersions(_ data: Data) throws -> [ComponentVersion] {
        try lossyList(data, decode: CLIVersionComponent.self).map {
            ComponentVersion(
                appName: $0.appName, version: $0.version,
                buildType: $0.buildType ?? "", commit: $0.commit ?? "")
        }
    }

    // MARK: - Networks

    public static func parseNetworks(_ data: Data) throws -> [NetworkSummary] {
        try lossyList(data, decode: CLINetworkRecord.self).map { record in
            NetworkSummary(
                id: record.id,
                name: record.configuration.name,
                mode: record.configuration.mode,
                gateway: record.status?.ipv4Gateway,
                subnet: record.status?.ipv4Subnet,
                plugin: record.configuration.plugin,
                ipv6Subnet: record.status?.ipv6Subnet,
                labels: record.configuration.labels ?? [:],
                createdAt: record.configuration.creationDate,
                isBuiltin: record.isBuiltin
            )
        }
    }

    // MARK: - Volumes / registries / machines / builder

    public static func parseVolumes(_ data: Data) throws -> [VolumeSummary] {
        try lossyList(data, decode: CLIVolumeRecord.self).compactMap { record in
            guard let name = record.resolvedName else { return nil }
            return VolumeSummary(
                name: name,
                source: record.resolvedSource,
                sizeBytes: record.resolvedSizeBytes,
                options: record.resolvedOptions,
                labels: record.resolvedLabels,
                createdAt: record.resolvedCreatedAt
            )
        }
    }

    public static func parseDNS(_ data: Data) throws -> [DNSDomainSummary] {
        try lossyList(data, decode: CLIDNSRecord.self).compactMap { record in
            guard let domain = record.resolvedDomain else { return nil }
            return DNSDomainSummary(domain: domain, localhostIP: record.localhost)
        }
    }

    public static func parseRegistries(_ data: Data) throws -> [RegistrySummary] {
        try lossyList(data, decode: CLIRegistryRecord.self).compactMap { record in
            guard let server = record.server ?? record.host else { return nil }
            return RegistrySummary(server: server)
        }
    }

    public static func parseMachines(_ data: Data) throws -> [MachineSummary] {
        try lossyList(data, decode: CLIMachineRecord.self).compactMap(Self.machine(from:))
    }

    /// Parses `machine inspect` output into a `MachineSummary`.
    /// The real CLI emits an array of one object; a bare single-object fallback is also
    /// tried so that both shapes succeed.
    public static func parseMachine(_ data: Data) -> MachineSummary? {
        if let first = (try? parseMachines(data))?.first { return first }
        if let one = try? decoder.decode(CLIMachineRecord.self, from: data) {
            return machine(from: one)
        }
        return nil
    }

    private static func machine(from record: CLIMachineRecord) -> MachineSummary? {
        guard let name = record.id else { return nil }
        return MachineSummary(
            name: name, state: record.status, createdAt: record.createdDate,
            ipAddress: record.ipAddress, cpus: record.cpus,
            memory: formatBinarySize(record.memory),
            disk: formatBinarySize(record.diskSize),
            isDefault: record.isDefault ?? false,
            kernel: nil, nestedVirtualization: nil,
            homeMount: record.homeMount)
    }

    /// Formats a raw byte count into a human-readable binary size string matching the
    /// CLI table display: "2G", "75M", etc. Exact multiples emit an integer suffix;
    /// non-exact multiples emit one decimal place (e.g. "1.5G").
    private static func formatBinarySize(_ bytes: Int64?) -> String? {
        guard let bytes else { return nil }
        let units: [(String, Int64)] = [("G", 1 << 30), ("M", 1 << 20), ("K", 1 << 10)]
        for (suffix, unit) in units where bytes >= unit {
            if bytes % unit == 0 { return "\(bytes / unit)\(suffix)" }
            return String(format: "%.1f%@", Double(bytes) / Double(unit), suffix)
        }
        return "\(bytes)B"
    }

    /// The builder is considered running when at least one record reports a `running`
    /// state. An empty list (no builder configured) reports not-running.
    public static func parseBuilderStatus(_ data: Data) throws -> BuilderStatus {
        let records = try lossyList(data, decode: CLIBuilderRecord.self)
        let running = records.contains { ($0.state ?? "").lowercased() == "running" }
        return BuilderStatus(isRunning: running)
    }

    // MARK: - System df

    public static func parseDiskUsage(_ data: Data) throws -> StorageUsage {
        let record: CLIDiskUsageRecord
        do {
            record = try decoder.decode(CLIDiskUsageRecord.self, from: data)
        } catch {
            throw BackendError.decodingFailed(String(describing: error))
        }
        func map(_ c: CLIDiskUsageRecord.Category) -> CategoryUsage {
            CategoryUsage(
                total: c.total, active: c.active,
                sizeInBytes: c.sizeInBytes, reclaimable: c.reclaimable)
        }
        return StorageUsage(
            images: map(record.images),
            containers: map(record.containers),
            volumes: map(record.volumes))
    }

    // MARK: - Lenient decoding

    /// Decodes a JSON array element-by-element, dropping (rather than throwing on)
    /// elements that fail to decode. Throws only when the top level is not a JSON array.
    static func lossyList<Element: Decodable>(
        _ data: Data,
        decode _: Element.Type
    ) throws -> [Element] {
        do {
            let wrappers = try decoder.decode([Lossy<Element>].self, from: data)
            return wrappers.compactMap(\.value)
        } catch {
            throw BackendError.decodingFailed(String(describing: error))
        }
    }
}

/// A decoding wrapper that yields `nil` instead of throwing when its element fails to
/// decode, letting a surrounding array skip malformed entries.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(Value.self)
    }
}
