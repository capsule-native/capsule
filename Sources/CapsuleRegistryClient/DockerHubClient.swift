//
//  DockerHubClient.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The unauthenticated Docker Hub catalog adapter, conforming to the backend's
//  `ImageRegistrySearching` port. hub.docker.com is treated as an unstable third-party
//  API: wire structs are decoded defensively (unknown fields ignored, malformed rows
//  dropped, pagination tolerant of null/empty), and every failure maps into
//  `RegistrySearchError` — a 429 becomes `rateLimited` so the domain can cool down
//  instead of retrying.

import CapsuleBackend
import Foundation

/// The transport seam: how the client performs one HTTP request. `URLSession` in
/// production; a recording stub in tests (mirroring `ProcessRunning` in the CLI adapter).
public protocol HTTPDataFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The live `URLSession`-backed transport.
public struct URLSessionDataFetcher: HTTPDataFetching {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RegistrySearchError.network(message: "The response was not HTTP.")
        }
        return (data, http)
    }
}

/// Searches Docker Hub's public v2 catalog API — no API key, no login, no credentials.
public struct DockerHubClient: ImageRegistrySearching {
    /// Docker Hub's page size for both endpoints; the domain's pagination assumes it.
    public static let pageSize = 25

    private let fetcher: any HTTPDataFetching

    public init() {
        self.init(fetcher: URLSessionDataFetcher())
    }

    /// The seam init used by tests to record requests and replay canned responses.
    init(fetcher: any HTTPDataFetching) {
        self.fetcher = fetcher
    }

    public func searchRepositories(
        query: String, page: Int
    ) async throws
        -> RegistryRepositoryPage
    {
        var components = Self.baseComponents
        components.path = "/v2/search/repositories/"
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(Self.pageSize)),
        ]
        let data = try await fetch(components)
        let response = try Self.decode(HubSearchResponse.self, from: data)
        let items = (response.results ?? []).compactMap(\.value)
            .compactMap { (result: HubSearchResult) -> RegistryRepositorySummary? in
                guard let name = result.repoName, !name.isEmpty else { return nil }
                return RegistryRepositorySummary(
                    name: name,
                    shortDescription: result.shortDescription.flatMap {
                        $0.isEmpty ? nil : $0
                    },
                    starCount: result.starCount,
                    pullCount: result.pullCount,
                    isOfficial: result.isOfficial ?? false
                )
            }
        return RegistryRepositoryPage(
            items: items,
            totalCount: response.count,
            hasNextPage: Self.hasNext(response.next)
        )
    }

    public func listTags(repository: String, page: Int) async throws -> RegistryTagPage {
        var components = Self.baseComponents
        components.path = "/v2/repositories/\(repository)/tags/"
        components.queryItems = [
            URLQueryItem(name: "page_size", value: String(Self.pageSize)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        let data = try await fetch(components)
        let response = try Self.decode(HubTagsResponse.self, from: data)
        let items = (response.results ?? []).compactMap(\.value)
            .compactMap { (result: HubTagResult) -> RegistryTagSummary? in
                guard let name = result.name, !name.isEmpty else { return nil }
                return RegistryTagSummary(
                    name: name,
                    lastUpdated: result.lastUpdated,
                    sizeBytes: result.fullSize,
                    digest: result.digest
                )
            }
        return RegistryTagPage(
            items: items,
            totalCount: response.count,
            hasNextPage: Self.hasNext(response.next)
        )
    }

    // MARK: - Transport

    private static var baseComponents: URLComponents {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "hub.docker.com"
        return components
    }

    /// Performs one GET, mapping transport failures into `RegistrySearchError` while
    /// letting cancellation (including `URLError.cancelled`) surface as
    /// `CancellationError` so a superseded search never looks like an outage.
    private func fetch(_ components: URLComponents) async throws -> Data {
        guard let url = components.url else {
            throw RegistrySearchError.network(message: "Could not compose the request URL.")
        }
        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Capsule (macOS)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await fetcher.data(for: request)
        } catch let error as RegistrySearchError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw RegistrySearchError.network(message: error.localizedDescription)
        } catch {
            throw RegistrySearchError.network(message: String(describing: error))
        }

        switch response.statusCode {
        case 200..<300:
            return data
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Int($0) }
            throw RegistrySearchError.rateLimited(retryAfterSeconds: retryAfter)
        default:
            throw RegistrySearchError.httpStatus(
                code: response.statusCode, message: Self.errorMessage(in: data))
        }
    }

    // MARK: - Decoding

    private static func decode<Value: Decodable>(
        _ type: Value.Type, from data: Data
    ) throws -> Value {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw RegistrySearchError.decodingFailed(String(describing: error))
        }
    }

    /// Hub marks "no further page" as either a JSON null or an empty string.
    private static func hasNext(_ next: String?) -> Bool {
        !(next ?? "").isEmpty
    }

    /// Hub error bodies carry a short `message` field; surface it when present.
    private static func errorMessage(in data: Data) -> String? {
        let decoder = JSONDecoder()
        return (try? decoder.decode(HubErrorBody.self, from: data))?.message
    }
}

// MARK: - Wire types (hub.docker.com v2)

/// Decodes each array element independently so one malformed row is dropped rather than
/// blanking the whole page (the `OutputParser.lossyList` idiom).
private struct Lossy<Element: Decodable>: Decodable {
    var value: Element?

    init(from decoder: any Decoder) throws {
        value = try? Element(from: decoder)
    }
}

private struct HubSearchResponse: Decodable {
    var count: Int?
    var next: String?
    var results: [Lossy<HubSearchResult>]?
}

private struct HubSearchResult: Decodable {
    var repoName: String?
    var shortDescription: String?
    var starCount: Int?
    var pullCount: Int64?
    var isOfficial: Bool?
}

private struct HubTagsResponse: Decodable {
    var count: Int?
    var next: String?
    var results: [Lossy<HubTagResult>]?
}

private struct HubTagResult: Decodable {
    var name: String?
    var lastUpdated: String?
    var fullSize: Int64?
    var digest: String?
}

private struct HubErrorBody: Decodable {
    var message: String?
}
