//
//  ImageRegistrySearch.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The image-registry search port: browsing a registry's public catalog (repositories and
//  tags) over its HTTP API, without authentication. Deliberately a separate protocol from
//  `ContainerBackend` — search speaks a registry's web API, not the `container` CLI — so
//  additional registries can be adapted later without widening the container port.

/// Searches a container-image registry's public catalog.
///
/// Implementations surface failures as `RegistrySearchError` and let cancellation
/// propagate as `CancellationError`, so callers can tell a superseded request apart from
/// a real failure.
public protocol ImageRegistrySearching: Sendable {
    /// One page (1-based) of repositories matching `query`.
    func searchRepositories(query: String, page: Int) async throws -> RegistryRepositoryPage

    /// One page (1-based) of tags for a namespaced repository path (e.g. `library/nginx`).
    func listTags(repository: String, page: Int) async throws -> RegistryTagPage
}

/// A registry's lightweight view of one repository search hit. `name` is the repository
/// path exactly as the registry returns it (official images carry no namespace, e.g.
/// "nginx"); the domain maps this into its own model so wire shapes never reach the UI.
public struct RegistryRepositorySummary: Sendable, Equatable, Identifiable, Codable {
    public var name: String
    public var shortDescription: String?
    public var starCount: Int?
    public var pullCount: Int64?
    public var isOfficial: Bool
    /// The repository's logo/avatar image URL as the registry reports it (raw string;
    /// the domain parses it into a `URL`). Nil when the registry has none — the UI shows
    /// its default artwork instead.
    public var logoURL: String?

    public var id: String { name }

    public init(
        name: String, shortDescription: String? = nil, starCount: Int? = nil,
        pullCount: Int64? = nil, isOfficial: Bool = false, logoURL: String? = nil
    ) {
        self.name = name
        self.shortDescription = shortDescription
        self.starCount = starCount
        self.pullCount = pullCount
        self.isOfficial = isOfficial
        self.logoURL = logoURL
    }
}

/// A registry's lightweight view of one tag. `lastUpdated` is the raw ISO-8601 string the
/// registry emits (the domain parses it into a `Date`).
public struct RegistryTagSummary: Sendable, Equatable, Identifiable, Codable {
    public var name: String
    public var lastUpdated: String?
    public var sizeBytes: Int64?
    public var digest: String?

    public var id: String { name }

    public init(
        name: String, lastUpdated: String? = nil, sizeBytes: Int64? = nil,
        digest: String? = nil
    ) {
        self.name = name
        self.lastUpdated = lastUpdated
        self.sizeBytes = sizeBytes
        self.digest = digest
    }
}

/// One page of repository search results, with enough pagination state for "Load More".
public struct RegistryRepositoryPage: Sendable, Equatable, Codable {
    public var items: [RegistryRepositorySummary]
    public var totalCount: Int?
    public var hasNextPage: Bool

    public init(
        items: [RegistryRepositorySummary] = [], totalCount: Int? = nil,
        hasNextPage: Bool = false
    ) {
        self.items = items
        self.totalCount = totalCount
        self.hasNextPage = hasNextPage
    }
}

/// One page of a repository's tags, with enough pagination state for "Load More".
public struct RegistryTagPage: Sendable, Equatable, Codable {
    public var items: [RegistryTagSummary]
    public var totalCount: Int?
    public var hasNextPage: Bool

    public init(
        items: [RegistryTagSummary] = [], totalCount: Int? = nil, hasNextPage: Bool = false
    ) {
        self.items = items
        self.totalCount = totalCount
        self.hasNextPage = hasNextPage
    }
}

/// Errors a registry-search adapter may surface. The domain maps these into display
/// state; `rateLimited` deliberately stands apart so a 429 can become a cooldown rather
/// than a retry loop.
public enum RegistrySearchError: Error, Sendable, Equatable {
    /// The registry rejected the request for exceeding its per-IP rate limit (HTTP 429).
    case rateLimited(retryAfterSeconds: Int?)
    /// Any other non-success HTTP status (e.g. 404 for an unknown repository).
    case httpStatus(code: Int, message: String?)
    /// The request never produced an HTTP response (offline, DNS failure, timeout…).
    case network(message: String)
    /// The response body could not be decoded.
    case decodingFailed(String)
}
