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
                sizeBytes: record.configuration.descriptor.size
            )
        }
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
                createdAt: record.configuration.creationDate
            )
        }
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

    // MARK: - Networks

    public static func parseNetworks(_ data: Data) throws -> [NetworkSummary] {
        try lossyList(data, decode: CLINetworkRecord.self).map { record in
            NetworkSummary(
                id: record.id,
                name: record.configuration.name,
                mode: record.configuration.mode,
                gateway: record.status?.ipv4Gateway,
                subnet: record.status?.ipv4Subnet
            )
        }
    }

    // MARK: - Volumes / registries / machines / builder

    public static func parseVolumes(_ data: Data) throws -> [VolumeSummary] {
        try lossyList(data, decode: CLIVolumeRecord.self).compactMap { record in
            guard let name = record.name else { return nil }
            return VolumeSummary(name: name, source: record.source)
        }
    }

    public static func parseRegistries(_ data: Data) throws -> [RegistrySummary] {
        try lossyList(data, decode: CLIRegistryRecord.self).compactMap { record in
            guard let server = record.server ?? record.host else { return nil }
            return RegistrySummary(server: server)
        }
    }

    public static func parseMachines(_ data: Data) throws -> [MachineSummary] {
        try lossyList(data, decode: CLIMachineRecord.self).compactMap { record in
            guard let name = record.name else { return nil }
            return MachineSummary(name: name, state: record.state)
        }
    }

    /// The builder is considered running when at least one record reports a `running`
    /// state. An empty list (no builder configured) reports not-running.
    public static func parseBuilderStatus(_ data: Data) throws -> BuilderStatus {
        let records = try lossyList(data, decode: CLIBuilderRecord.self)
        let running = records.contains { ($0.state ?? "").lowercased() == "running" }
        return BuilderStatus(isRunning: running)
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
