//
//  ContainerCLIRelease.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The container-CLI release port: looking up apple/container's latest GitHub release and
//  downloading its signed installer package. Deliberately a separate protocol from
//  `ContainerBackend` — installing/updating the CLI cannot be done by running the CLI —
//  and from the registry-search port, which speaks an image registry's catalog API.

import Foundation

public struct ContainerCLIReleaseAsset: Sendable, Equatable, Codable {
    public var name: String
    public var downloadURL: String

    public init(name: String, downloadURL: String) {
        self.name = name
        self.downloadURL = downloadURL
    }
}

public struct ContainerCLIRelease: Sendable, Equatable, Codable {
    public var tag: String
    public var assets: [ContainerCLIReleaseAsset]

    public init(tag: String, assets: [ContainerCLIReleaseAsset]) {
        self.tag = tag
        self.assets = assets
    }

    /// The signed installer package to install, or nil when the release carries none.
    /// Releases publish either `container-installer-signed.pkg` or the versioned
    /// `container-<tag>-installer-signed.pkg` (1.0.0 uses the latter); unsigned packages
    /// are never selected.
    public var signedInstallerAsset: ContainerCLIReleaseAsset? {
        assets.first { $0.name == "container-installer-signed.pkg" }
            ?? assets.first { $0.name == "container-\(tag)-installer-signed.pkg" }
    }
}

/// Errors a release-source adapter may surface. `rateLimited` stands apart so a 429 can
/// become a cooldown message rather than a retry loop; `noSignedPackage` is thrown by
/// callers when ``ContainerCLIRelease/signedInstallerAsset`` is nil.
public enum ContainerReleaseError: Error, Sendable, Equatable {
    case rateLimited(retryAfterSeconds: Int?)
    case httpStatus(code: Int, message: String?)
    case network(message: String)
    case decodingFailed(String)
    case noSignedPackage(tag: String)
}

/// Looks up and downloads apple/container releases.
public protocol ContainerReleaseSource: Sendable {
    /// The latest published release (tag + downloadable assets).
    func latestRelease() async throws -> ContainerCLIRelease

    /// Downloads `asset` to `destination`, yielding human-readable progress lines
    /// (`NN%` tokens drive determinate task progress). The stream finishing without a
    /// throw means `destination` holds the complete package; cancellation and failures
    /// remove the partial file.
    func downloadPackage(
        _ asset: ContainerCLIReleaseAsset, to destination: URL
    )
        -> AsyncThrowingStream<OutputLine, Error>
}
