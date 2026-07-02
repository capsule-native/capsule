//
//  MockContainerReleaseSource.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The in-memory release source for tests, previews, and the golden-UI-test mode:
//  seedable release, scripted progress lines, recorded download calls, optional failure.

import Foundation

public final class MockContainerReleaseSource: ContainerReleaseSource, @unchecked Sendable {
    private let lock = NSLock()
    private var releaseValue: ContainerCLIRelease
    private var failureValue: ContainerReleaseError?
    private var lastDownloadedAssetValue: ContainerCLIReleaseAsset?

    public init(
        release: ContainerCLIRelease = ContainerCLIRelease(
            tag: "1.2.3",
            assets: [
                ContainerCLIReleaseAsset(
                    name: "container-installer-signed.pkg",
                    downloadURL: "https://example.com/container-installer-signed.pkg")
            ])
    ) {
        self.releaseValue = release
    }

    /// When set, `latestRelease` and `downloadPackage` fail with this error.
    public var failure: ContainerReleaseError? {
        get { lock.withLock { failureValue } }
        set { lock.withLock { failureValue = newValue } }
    }

    /// The asset passed to the most recent `downloadPackage` call.
    public var lastDownloadedAsset: ContainerCLIReleaseAsset? {
        lock.withLock { lastDownloadedAssetValue }
    }

    public func latestRelease() async throws -> ContainerCLIRelease {
        try lock.withLock {
            if let failureValue { throw failureValue }
            return releaseValue
        }
    }

    public func downloadPackage(
        _ asset: ContainerCLIReleaseAsset, to destination: URL
    ) -> AsyncThrowingStream<OutputLine, Error> {
        let failure = lock.withLock { failureValue }
        lock.withLock { lastDownloadedAssetValue = asset }
        return AsyncThrowingStream { continuation in
            if let failure {
                continuation.finish(throwing: failure)
                return
            }
            for percent in [25, 50, 75, 100] {
                continuation.yield(OutputLine(source: .stdout, text: "\(percent)%"))
            }
            FileManager.default.createFile(atPath: destination.path, contents: Data())
            continuation.finish()
        }
    }
}
