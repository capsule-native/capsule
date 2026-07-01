//
//  MockImageRegistry.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  An in-memory `ImageRegistrySearching` for tests, previews, and UI-test mode: seeded
//  pages keyed by query (with a "*" wildcard fallback), a settable failure, an optional
//  response delay so cancellation windows can be exercised, and call spies mirroring
//  `MockBackend`'s conventions.

import Foundation

public final class MockImageRegistry: ImageRegistrySearching, @unchecked Sendable {
    /// Wildcard key: pages served for any query (or repository) without an exact entry.
    public static let anyQuery = "*"

    /// When set, every call throws this error (after any `responseDelay`).
    public var failure: RegistrySearchError?
    /// When set, calls sleep first — a cancellable window for debounce/supersede tests.
    public var responseDelay: Duration?

    public private(set) var searchCallCount = 0
    public private(set) var searchQueries: [String] = []
    public private(set) var lastSearchQuery: String?
    public private(set) var lastSearchPage: Int?
    public private(set) var tagsCallCount = 0
    public private(set) var lastTagsRepository: String?
    public private(set) var lastTagsPage: Int?

    private let lock = NSLock()
    private let searchPages: [String: [Int: RegistryRepositoryPage]]
    private let tagPages: [String: [Int: RegistryTagPage]]

    public init(
        searchPages: [String: [Int: RegistryRepositoryPage]] = [:],
        tagPages: [String: [Int: RegistryTagPage]] = [:]
    ) {
        self.searchPages = searchPages
        self.tagPages = tagPages
    }

    /// Seeds a single results page served for every query, and one tags page per
    /// namespaced repository — enough for previews and straightforward tests.
    public convenience init(
        repositories: [RegistryRepositorySummary],
        tags: [String: [RegistryTagSummary]] = [:]
    ) {
        self.init(
            searchPages: [Self.anyQuery: [1: RegistryRepositoryPage(items: repositories)]],
            tagPages: tags.mapValues { [1: RegistryTagPage(items: $0)] }
        )
    }

    public func searchRepositories(
        query: String, page: Int
    ) async throws
        -> RegistryRepositoryPage
    {
        lock.lock()
        searchCallCount += 1
        searchQueries.append(query)
        lastSearchQuery = query
        lastSearchPage = page
        let delay = responseDelay
        let pendingFailure = failure
        let result = (searchPages[query] ?? searchPages[Self.anyQuery])?[page]
        lock.unlock()
        if let delay { try await Task.sleep(for: delay) }
        try Task.checkCancellation()
        if let pendingFailure { throw pendingFailure }
        return result ?? RegistryRepositoryPage()
    }

    public func listTags(repository: String, page: Int) async throws -> RegistryTagPage {
        lock.lock()
        tagsCallCount += 1
        lastTagsRepository = repository
        lastTagsPage = page
        let delay = responseDelay
        let pendingFailure = failure
        let result = (tagPages[repository] ?? tagPages[Self.anyQuery])?[page]
        lock.unlock()
        if let delay { try await Task.sleep(for: delay) }
        try Task.checkCancellation()
        if let pendingFailure { throw pendingFailure }
        return result ?? RegistryTagPage()
    }
}

extension MockImageRegistry {
    /// A believable little catalog for previews and `CAPSULE_UITEST` mode.
    public static func sample() -> MockImageRegistry {
        MockImageRegistry(
            repositories: [
                RegistryRepositorySummary(
                    name: "nginx", shortDescription: "Official build of Nginx.",
                    starCount: 21318, pullCount: 13_114_222_271, isOfficial: true),
                RegistryRepositorySummary(
                    name: "nginx/nginx-ingress",
                    shortDescription: "NGINX Ingress Controllers for Kubernetes",
                    starCount: 121, pullCount: 1_085_932_916, isOfficial: false),
                RegistryRepositorySummary(
                    name: "redis",
                    shortDescription: "Redis is an open-source in-memory data store.",
                    starCount: 13342, pullCount: 6_123_456_789, isOfficial: true),
            ],
            tags: [
                "library/nginx": [
                    RegistryTagSummary(
                        name: "latest", lastUpdated: "2026-06-25T22:52:42.349783Z",
                        sizeBytes: 75_271_303),
                    RegistryTagSummary(
                        name: "1.31.2", lastUpdated: "2026-06-24T04:51:06.973034Z",
                        sizeBytes: 75_271_303),
                    RegistryTagSummary(
                        name: "alpine", lastUpdated: "2026-06-24T04:51:07.402177Z",
                        sizeBytes: 21_004_231),
                ],
                "nginx/nginx-ingress": [
                    RegistryTagSummary(
                        name: "latest", lastUpdated: "2026-06-18T11:13:06.243030Z",
                        sizeBytes: 91_120_020)
                ],
                "library/redis": [
                    RegistryTagSummary(
                        name: "latest", lastUpdated: "2026-06-20T09:00:00Z",
                        sizeBytes: 42_820_110)
                ],
            ]
        )
    }
}
