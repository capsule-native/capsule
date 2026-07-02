//
//  GitHubReleaseClient.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The apple/container GitHub-releases adapter, conforming to the backend's
//  `ContainerReleaseSource` port. Release lookup goes through the same `HTTPDataFetching`
//  seam as the Docker Hub adapter (stub-testable); the large package download streams
//  through `URLSession.bytes` directly, yielding `NN%` progress lines.

import CapsuleBackend
import Foundation

public struct GitHubReleaseClient: ContainerReleaseSource {
    private let fetcher: any HTTPDataFetching
    private let session: URLSession

    public init() {
        self.init(fetcher: URLSessionDataFetcher())
    }

    /// The seam init used by tests to record requests and replay canned responses.
    init(fetcher: any HTTPDataFetching, session: URLSession = .shared) {
        self.fetcher = fetcher
        self.session = session
    }

    public func latestRelease() async throws -> ContainerCLIRelease {
        let url = URL(string: "https://api.github.com/repos/apple/container/releases/latest")!
        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Capsule (macOS)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await fetcher.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw ContainerReleaseError.network(message: error.localizedDescription)
        } catch let error as ContainerReleaseError {
            throw error
        } catch {
            throw ContainerReleaseError.network(message: String(describing: error))
        }

        switch response.statusCode {
        case 200..<300:
            break
        case 403, 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Int($0) }
            throw ContainerReleaseError.rateLimited(retryAfterSeconds: retryAfter)
        default:
            throw ContainerReleaseError.httpStatus(
                code: response.statusCode, message: Self.errorMessage(in: data))
        }

        let wire: GitHubRelease
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            wire = try decoder.decode(GitHubRelease.self, from: data)
        } catch {
            throw ContainerReleaseError.decodingFailed(String(describing: error))
        }
        guard let tag = wire.tagName, !tag.isEmpty else {
            throw ContainerReleaseError.decodingFailed("release JSON carries no tag_name")
        }
        let assets = (wire.assets ?? []).compactMap { asset -> ContainerCLIReleaseAsset? in
            guard let name = asset.name, let url = asset.browserDownloadUrl else { return nil }
            return ContainerCLIReleaseAsset(name: name, downloadURL: url)
        }
        return ContainerCLIRelease(tag: tag, assets: assets)
    }

    public func downloadPackage(
        _ asset: ContainerCLIReleaseAsset, to destination: URL
    ) -> AsyncThrowingStream<OutputLine, Error> {
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: asset.downloadURL) else {
                        throw ContainerReleaseError.network(
                            message: "Invalid download URL for \(asset.name).")
                    }
                    guard url.scheme == "https" else {
                        throw ContainerReleaseError.network(
                            message: "Refusing non-HTTPS download URL for \(asset.name).")
                    }
                    var request = URLRequest(url: url)
                    request.setValue("Capsule (macOS)", forHTTPHeaderField: "User-Agent")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                        (200..<300).contains(http.statusCode)
                    else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw ContainerReleaseError.httpStatus(code: code, message: nil)
                    }
                    continuation.yield(
                        OutputLine(source: .stdout, text: "Downloading \(asset.name)…"))
                    let total = response.expectedContentLength
                    FileManager.default.createFile(atPath: destination.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: destination)
                    defer { try? handle.close() }
                    var buffer = Data()
                    buffer.reserveCapacity(1 << 16)
                    var written: Int64 = 0
                    var lastPercent = -1
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= 1 << 16 {
                            try handle.write(contentsOf: buffer)
                            written += Int64(buffer.count)
                            buffer.removeAll(keepingCapacity: true)
                            if total > 0 {
                                let percent = Int(written * 100 / total)
                                if percent != lastPercent {
                                    lastPercent = percent
                                    continuation.yield(
                                        OutputLine(source: .stdout, text: "\(percent)%"))
                                }
                            }
                        }
                    }
                    if !buffer.isEmpty {
                        try handle.write(contentsOf: buffer)
                        written += Int64(buffer.count)
                    }
                    continuation.yield(
                        OutputLine(
                            source: .stdout,
                            text: "Downloaded \(asset.name) (\(written) bytes)."))
                    continuation.finish()
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// GitHub error bodies carry a short `message` field; surface it when present.
    private static func errorMessage(in data: Data) -> String? {
        struct Body: Decodable { var message: String? }
        return (try? JSONDecoder().decode(Body.self, from: data))?.message
    }
}

// MARK: - Wire types (api.github.com)

private struct GitHubRelease: Decodable {
    var tagName: String?
    var assets: [GitHubAsset]?
}

private struct GitHubAsset: Decodable {
    var name: String?
    var browserDownloadUrl: String?
}
