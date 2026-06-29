//
//  WireModels.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  `Decodable` mirrors of the `container` CLI's `--format json` payloads, captured
//  from the real CLI (v1.0.0) and cross-checked against the apple/container sources.
//
//  These intentionally decode only the fields Capsule renders today. Decoding a narrow
//  subset keeps us resilient to schema drift in unrelated fields: a new or renamed key
//  elsewhere in the payload does not break the row we care about. The adapter maps these
//  wire types into the port's clean value types (`ContainerSummary`, `ImageSummary`, …)
//  so wire shapes never leak past `CapsuleCLIBackend`.

import Foundation

// MARK: - Images

/// One element of `container image ls --format json` / `container image inspect`.
///
/// Shape (real capture):
/// ```
/// { "id": "<digest>",
///   "configuration": { "name": "docker.io/library/alpine:latest",
///                       "descriptor": { "digest": "...", "mediaType": "...", "size": 9218 } },
///   "variants": [ … ] }
/// ```
struct CLIImageRecord: Decodable {
    let id: String
    let configuration: Configuration

    struct Configuration: Decodable {
        let name: String
        let descriptor: Descriptor
        let creationDate: String?

        struct Descriptor: Decodable {
            let digest: String
            let mediaType: String
            let size: Int64
        }
    }
}

// MARK: - Containers

/// One element of `container ls --format json`. The CLI encodes `ManagedContainer`
/// values, i.e. `{ id, configuration, status }` where `status` nests the runtime
/// `state` and the network `Attachment`s.
struct CLIContainerRecord: Decodable {
    let id: String
    let configuration: Configuration
    let status: Status

    struct Configuration: Decodable {
        let id: String
        let image: ImageDescription
        let creationDate: String?
        // The CLI lists *configured* attachments here — the cross-reference source.
        // `mounts[].type.volume.name` is the attached volume name; the configured
        // `networks[].network` is the network NAME (distinct from `Status.Attachment`,
        // which carries addresses, not names).
        let mounts: [ConfiguredMount]?
        let networks: [ConfiguredNetwork]?

        struct ImageDescription: Decodable {
            let reference: String
        }

        struct ConfiguredMount: Decodable {
            // A volume mount carries the volume NAME at `type.volume.name`.
            // `source` is the host path (volume.img), NOT the name; bind mounts
            // have no `type.volume`. Verified against the real CLI capture.
            let type: MountType?
            struct MountType: Decodable {
                let volume: VolumeRef?
                struct VolumeRef: Decodable { let name: String }
            }
            /// The attached volume's name, or nil for a non-volume (bind) mount.
            var volumeName: String? { type?.volume?.name }
        }

        struct ConfiguredNetwork: Decodable {
            let network: String?
        }
    }

    struct Status: Decodable {
        let state: String
        let networks: [Attachment]

        struct Attachment: Decodable {
            // The CLI moved from `address`/`gateway` to `ipv4Address`/`ipv4Gateway`
            // but still emits the legacy keys for compatibility; accept either.
            let ipv4Address: String?
            let address: String?

            /// The interface address without its CIDR prefix length, e.g.
            /// `192.168.64.3/24` → `192.168.64.3`.
            var ipAddress: String? {
                let cidr = ipv4Address ?? address
                return cidr?.split(separator: "/").first.map(String.init)
            }
        }
    }
}

// MARK: - Stats

/// One element of `container stats --format json`. Mirror of the source `ContainerStats`
/// struct; keys equal property names (no custom CodingKeys). Only `id` is required.
struct CLIContainerStatsRecord: Decodable {
    let id: String
    let cpuUsageUsec: UInt64?
    let memoryUsageBytes: UInt64?
    let memoryLimitBytes: UInt64?
    let networkRxBytes: UInt64?
    let networkTxBytes: UInt64?
    let blockReadBytes: UInt64?
    let blockWriteBytes: UInt64?
    let numProcesses: UInt64?
}

// MARK: - System version

/// One element of `container system version --format json`. The CLI emits one entry
/// per component, e.g. `container` (the client) and `container-apiserver` (the server).
struct CLIVersionComponent: Decodable {
    let appName: String
    let version: String
    let buildType: String?
    let commit: String?
}

// MARK: - Networks

/// One element of `container network ls --format json` (real capture):
/// ```
/// { "id": "default",
///   "configuration": { "name": "default", "mode": "nat", … },
///   "status": { "ipv4Gateway": "192.168.64.1", "ipv4Subnet": "192.168.64.0/24", … } }
/// ```
struct CLINetworkRecord: Decodable {
    let id: String
    let configuration: Configuration
    let status: Status?

    struct Configuration: Decodable {
        let name: String
        let mode: String?
        let plugin: String?
        let labels: [String: String]?
        let options: [String: String]?
        let creationDate: String?
    }

    struct Status: Decodable {
        let ipv4Gateway: String?
        let ipv4Subnet: String?
        let ipv6Subnet: String?
    }

    /// Runtime-managed networks (e.g. `default`) carry this label and must not be deleted.
    var isBuiltin: Bool {
        configuration.labels?["com.apple.container.resource.role"] == "builtin"
    }
}

// MARK: - Volumes / registries / machines / builder
//
// These families were observed only in their empty form on the dev machine, so the
// decoders read an all-optional best-effort subset. Combined with lenient list
// decoding, an unverified populated shape degrades to an empty/partial list rather than
// crashing.

// Real-capture shape: `container volume list/inspect` nests fields under `configuration`
// (sizeInBytes/driver/format/options/labels/creationDate) with a top-level `id`. This
// nested shape supersedes the flat sketch in contract Appendix A §4.4; the flat name/source
// fields remain only as lenient fallbacks for an alternate/older shape.
struct CLIVolumeRecord: Decodable {
    let id: String?
    let configuration: Configuration?
    // Flat fallbacks for an alternate/older shape (keeps lenient decode tolerant).
    let name: String?
    let source: String?

    struct Configuration: Decodable {
        let name: String?
        let source: String?
        let driver: String?
        let format: String?
        let labels: [String: String]?
        let options: [String: String]?
        let sizeInBytes: Int64?
        let creationDate: String?
    }

    var resolvedName: String? { configuration?.name ?? name ?? id }
    var resolvedSource: String? { configuration?.source ?? source }
    var resolvedSizeBytes: Int64? { configuration?.sizeInBytes }
    var resolvedOptions: [String: String] { configuration?.options ?? [:] }
    var resolvedLabels: [String: String] { configuration?.labels ?? [:] }
    var resolvedCreatedAt: String? { configuration?.creationDate }
}

/// One element of `container system dns list --format json`. **Verified against the live
/// CLI:** the list emits an array of bare domain-name STRINGS (e.g. `["test"]`) — it does NOT
/// return objects, and it never echoes the create-time `--localhost` IP. We decode that
/// string form, and ALSO tolerate an object form (`domainName`/`domain`/`name` + `localhost`)
/// so a future build that adds detail still parses. Lenient + all-optional, like the other
/// families.
struct CLIDNSRecord: Decodable {
    let domainName: String?
    let domain: String?
    let name: String?
    let localhost: String?

    var resolvedDomain: String? { domainName ?? domain ?? name }

    private enum CodingKeys: String, CodingKey { case domainName, domain, name, localhost }

    init(from decoder: Decoder) throws {
        // Real shape: a bare string. Try that first.
        if let single = try? decoder.singleValueContainer(),
            let value = try? single.decode(String.self)
        {
            domainName = value
            domain = nil
            name = nil
            localhost = nil
            return
        }
        // Drift tolerance: an object with name/localhost keys.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        domainName = try container.decodeIfPresent(String.self, forKey: .domainName)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        localhost = try container.decodeIfPresent(String.self, forKey: .localhost)
    }
}

struct CLIRegistryRecord: Decodable {
    let server: String?
    let host: String?
}

/// One element of `container machine list --format json` / `container machine inspect`.
///
/// Shape locked to the real CLI output (captured 2026-06-29):
/// ```
/// { "id": "capsule-probe", "status": "running", "cpus": 2,
///   "memory": 2147483648, "diskSize": 78643200,
///   "ipAddress": "192.168.64.9", "createdDate": "2026-06-29T20:03:11Z",
///   "default": true, "homeMount": "rw" }
/// ```
/// `id` is the machine NAME. `memory`/`diskSize` are raw bytes (Int64).
/// `default` is a Swift keyword, so it is mapped via `CodingKeys`.
struct CLIMachineRecord: Decodable {
    let id: String?
    let status: String?
    let cpus: Int?
    let memory: Int64?
    let diskSize: Int64?
    let ipAddress: String?
    let createdDate: String?
    let isDefault: Bool?
    let homeMount: String?

    enum CodingKeys: String, CodingKey {
        case id, status, cpus, memory, diskSize, ipAddress, createdDate, homeMount
        case isDefault = "default"
    }
}

struct CLIBuilderRecord: Decodable {
    let state: String?
}

// MARK: - System properties

/// A TOML/JSON scalar (Int, Double, Bool, or String) rendered to a display string.
enum JSONScalar: Decodable {
    case string(String), int(Int), double(Double), bool(Bool)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        self = .string(try c.decode(String.self))
    }
    var display: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        }
    }
}

// MARK: - System df

/// `container system df --format json` shape. Each category mixes item counts
/// (`total`/`active`) with byte totals (`reclaimable`/`sizeInBytes`).
struct CLIDiskUsageRecord: Decodable {
    let images: Category
    let containers: Category
    let volumes: Category

    struct Category: Decodable {
        let total: Int
        let active: Int
        let reclaimable: Int
        let sizeInBytes: Int
    }
}
