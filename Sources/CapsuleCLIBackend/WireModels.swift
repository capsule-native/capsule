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

        struct ImageDescription: Decodable {
            let reference: String
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

// MARK: - System version

/// One element of `container system version --format json`. The CLI emits one entry
/// per component, e.g. `container` (the client) and `container-apiserver` (the server).
struct CLIVersionComponent: Decodable {
    let appName: String
    let version: String
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
    }

    struct Status: Decodable {
        let ipv4Gateway: String?
        let ipv4Subnet: String?
    }
}

// MARK: - Volumes / registries / machines / builder
//
// These families were observed only in their empty form on the dev machine, so the
// decoders read an all-optional best-effort subset. Combined with lenient list
// decoding, an unverified populated shape degrades to an empty/partial list rather than
// crashing.

struct CLIVolumeRecord: Decodable {
    let name: String?
    let source: String?
}

struct CLIRegistryRecord: Decodable {
    let server: String?
    let host: String?
}

struct CLIMachineRecord: Decodable {
    let name: String?
    let state: String?
}

struct CLIBuilderRecord: Decodable {
    let state: String?
}
