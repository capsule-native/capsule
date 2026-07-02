//
//  RegistrySearchModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The Docker Hub
//  browse surface behind the Pull Image sheet: a debounced, cancellable catalog search
//  with per-(query, page) caching, "Load More" pagination, a tag picker, and an explicit
//  throttled state so an HTTP 429 becomes a cooldown, never a retry loop.

import CapsuleBackend
import Foundation
import Observation

/// The load state of a registry search (or tag listing), kept separate from the rows so
/// the UI can distinguish "throttled" and "failed" from "no results".
public enum RegistrySearchLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    /// The registry answered HTTP 429; searching resumes after a cooldown.
    case throttled
    case unavailable(ErrorDetail)
}

@MainActor
@Observable
public final class RegistrySearchModel {
    // MARK: Repositories

    public private(set) var loadState: RegistrySearchLoadState = .idle
    public private(set) var repositories: [RegistryRepository] = []
    public private(set) var hasMoreRepositories = false
    public private(set) var isLoadingMore = false
    /// A "Load More" failure to show inline; the loaded page-1 rows stay visible.
    public private(set) var loadMoreFailure: ErrorDetail?

    /// The live search text; edits are debounced into at most one in-flight search.
    public var searchText: String = "" {
        didSet { if searchText != oldValue { startSearch(afterDebounce: true) } }
    }

    // MARK: Tags

    public private(set) var selectedRepository: RegistryRepository?
    public private(set) var tagState: RegistrySearchLoadState = .idle
    public private(set) var tags: [RegistryTag] = []
    public private(set) var hasMoreTags = false
    public private(set) var isLoadingMoreTags = false
    /// A tag "Load More" failure to show inline; the loaded tag rows stay visible.
    public private(set) var tagLoadMoreFailure: ErrorDetail?

    private let client: any ImageRegistrySearching
    private let debounceInterval: Duration
    private let minimumQueryLength: Int
    private let cacheLifetime: Duration
    private let throttleCooldown: Duration

    private var searchTask: Task<Void, Never>?
    private var tagsTask: Task<Void, Never>?
    /// The query the visible `repositories` belong to — "Load More" pages only that
    /// query, so it can never mix result sets while an edit's debounce is pending.
    private var committedQuery: String?
    private var searchCache: [CacheKey: CacheEntry<RegistryRepositoryPage>] = [:]
    private var tagCache: [CacheKey: CacheEntry<RegistryTagPage>] = [:]
    private var throttledUntil: ContinuousClock.Instant?
    private var repositoryPage = 1
    private var tagPage = 1

    public init(
        client: any ImageRegistrySearching,
        debounceInterval: Duration = .milliseconds(400),
        minimumQueryLength: Int = 2,
        cacheLifetime: Duration = .seconds(300),
        throttleCooldown: Duration = .seconds(15)
    ) {
        self.client = client
        self.debounceInterval = debounceInterval
        self.minimumQueryLength = minimumQueryLength
        self.cacheLifetime = cacheLifetime
        self.throttleCooldown = throttleCooldown
    }

    // MARK: - Searching

    /// The query a search would run: trimmed, or nil while below the minimum length.
    public var effectiveQuery: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= minimumQueryLength ? trimmed : nil
    }

    /// Runs the search immediately (the field's submit action), skipping the debounce
    /// but keeping the single-flight, cache, and throttle semantics.
    public func searchNow() {
        startSearch(afterDebounce: false)
    }

    /// Fetches the next results page and appends it (the "Load More" affordance). A
    /// no-op while the search text no longer matches the loaded rows (an edit's debounce
    /// is pending) — the pending replacement search must win, not a mixed page append.
    public func loadMoreRepositories() {
        guard loadState == .loaded, hasMoreRepositories, !isLoadingMore,
            let query = committedQuery, query == effectiveQuery
        else { return }
        loadMoreFailure = nil
        isLoadingMore = true
        searchTask?.cancel()
        searchTask = Task { [weak self, repositoryPage] in
            await self?.runSearch(query: query, page: repositoryPage + 1, replacing: false)
        }
    }

    /// Cancels any pending debounce or in-flight request, then either clears the surface
    /// (query too short) or schedules the single replacement search.
    private func startSearch(afterDebounce: Bool) {
        searchTask?.cancel()
        isLoadingMore = false
        guard let query = effectiveQuery else {
            searchTask = nil
            repositories = []
            hasMoreRepositories = false
            loadMoreFailure = nil
            committedQuery = nil
            loadState = .idle
            return
        }
        let debounce = afterDebounce ? debounceInterval : .zero
        searchTask = Task { [weak self] in
            if debounce > .zero {
                do { try await Task.sleep(for: debounce) } catch { return }
            }
            await self?.runSearch(query: query, page: 1, replacing: true)
        }
    }

    private func runSearch(query: String, page: Int, replacing: Bool) async {
        // A fresh cache entry answers even during a throttle cooldown — serving it costs
        // no network call, which is the point of the cooldown.
        let key = CacheKey(scope: query, page: page)
        if let cached = searchCache[key], cached.expires > ContinuousClock.now {
            applySearchResult(cached.value, query: query, page: page, replacing: replacing)
            return
        }
        if let until = throttledUntil, ContinuousClock.now < until {
            if replacing {
                loadState = .throttled
            } else {
                isLoadingMore = false
                loadMoreFailure = Self.throttledDetail
            }
            return
        }
        if replacing { loadState = .loading }
        do {
            let result = try await client.searchRepositories(query: query, page: page)
            guard !Task.isCancelled else {
                isLoadingMore = false
                return
            }
            throttledUntil = nil
            searchCache[key] = CacheEntry(
                value: result, expires: ContinuousClock.now + cacheLifetime)
            pruneExpired(&searchCache)
            applySearchResult(result, query: query, page: page, replacing: replacing)
        } catch is CancellationError {
            isLoadingMore = false
        } catch {
            isLoadingMore = false
            guard !Task.isCancelled else { return }
            // A "Load More" failure must not blank the loaded rows: keep .loaded and
            // surface the failure inline. Full-pane states are for page-1 fetches.
            let state = failureState(for: error)
            if replacing {
                loadState = state
            } else {
                loadMoreFailure = Self.inlineDetail(for: state)
            }
        }
    }

    private func applySearchResult(
        _ result: RegistryRepositoryPage, query: String, page: Int, replacing: Bool
    ) {
        let mapped = result.items.map(RegistryRepository.init(summary:))
        if replacing {
            repositories = mapped
            repositoryPage = 1
        } else {
            let known = Set(repositories.map(\.id))
            repositories += mapped.filter { !known.contains($0.id) }
            repositoryPage = page
        }
        committedQuery = query
        hasMoreRepositories = result.hasNextPage
        isLoadingMore = false
        loadMoreFailure = nil
        loadState = .loaded
    }

    // MARK: - Tags

    /// Selects a repository and loads the first page of its tags.
    public func selectRepository(_ repository: RegistryRepository) {
        guard selectedRepository != repository else { return }
        selectedRepository = repository
        startTagLoad(for: repository)
    }

    /// Returns to the search results, cancelling any in-flight tag load.
    public func clearSelection() {
        tagsTask?.cancel()
        tagsTask = nil
        selectedRepository = nil
        tags = []
        hasMoreTags = false
        isLoadingMoreTags = false
        tagLoadMoreFailure = nil
        tagState = .idle
    }

    /// Reloads the selected repository's tags (the failure state's retry affordance).
    public func retryTags() {
        guard let repository = selectedRepository else { return }
        startTagLoad(for: repository)
    }

    /// Fetches the next page of tags and appends it.
    public func loadMoreTags() {
        guard tagState == .loaded, hasMoreTags, !isLoadingMoreTags,
            let repository = selectedRepository
        else { return }
        tagLoadMoreFailure = nil
        isLoadingMoreTags = true
        tagsTask?.cancel()
        tagsTask = Task { [weak self, tagPage] in
            await self?.runTagLoad(for: repository, page: tagPage + 1, replacing: false)
        }
    }

    private func startTagLoad(for repository: RegistryRepository) {
        tagsTask?.cancel()
        tags = []
        hasMoreTags = false
        isLoadingMoreTags = false
        tagLoadMoreFailure = nil
        tagState = .loading
        tagsTask = Task { [weak self] in
            await self?.runTagLoad(for: repository, page: 1, replacing: true)
        }
    }

    private func runTagLoad(
        for repository: RegistryRepository, page: Int, replacing: Bool
    ) async {
        guard selectedRepository == repository else { return }
        let key = CacheKey(scope: repository.namespacedName, page: page)
        if let cached = tagCache[key], cached.expires > ContinuousClock.now {
            applyTagResult(cached.value, page: page, replacing: replacing)
            return
        }
        if let until = throttledUntil, ContinuousClock.now < until {
            if replacing {
                tagState = .throttled
            } else {
                isLoadingMoreTags = false
                tagLoadMoreFailure = Self.throttledDetail
            }
            return
        }
        if replacing { tagState = .loading }
        do {
            let result = try await client.listTags(
                repository: repository.namespacedName, page: page)
            guard !Task.isCancelled, selectedRepository == repository else {
                isLoadingMoreTags = false
                return
            }
            throttledUntil = nil
            tagCache[key] = CacheEntry(
                value: result, expires: ContinuousClock.now + cacheLifetime)
            pruneExpired(&tagCache)
            applyTagResult(result, page: page, replacing: replacing)
        } catch is CancellationError {
            isLoadingMoreTags = false
        } catch {
            isLoadingMoreTags = false
            guard !Task.isCancelled, selectedRepository == repository else { return }
            let state = failureState(for: error)
            if replacing {
                tagState = state
            } else {
                tagLoadMoreFailure = Self.inlineDetail(for: state)
            }
        }
    }

    private func applyTagResult(_ result: RegistryTagPage, page: Int, replacing: Bool) {
        let mapped = result.items.map(RegistryTag.init(summary:))
        if replacing {
            tags = mapped
            tagPage = 1
        } else {
            let known = Set(tags.map(\.id))
            tags += mapped.filter { !known.contains($0.id) }
            tagPage = page
        }
        hasMoreTags = result.hasNextPage
        isLoadingMoreTags = false
        tagLoadMoreFailure = nil
        tagState = .loaded
    }

    // MARK: - Failures & cache

    /// A 429 arms the shared cooldown (honoring Retry-After when present) and surfaces
    /// as `.throttled`; everything else maps to a presentation-ready detail.
    private func failureState(for error: any Error) -> RegistrySearchLoadState {
        if case RegistrySearchError.rateLimited(let retryAfter) = error {
            let cooldown = retryAfter.map { Duration.seconds($0) } ?? throttleCooldown
            throttledUntil = ContinuousClock.now + cooldown
            return .throttled
        }
        return .unavailable(Self.detail(for: error))
    }

    /// The inline copy for a throttled "Load More" (the full pane keeps its rows).
    private static let throttledDetail = ErrorDetail(
        title: "Docker Hub is busy",
        explanation: "Docker Hub is throttling requests. Try again shortly.")

    /// Flattens a failure state into inline-notice copy for the "Load More" row.
    private static func inlineDetail(for state: RegistrySearchLoadState) -> ErrorDetail {
        if case .unavailable(let detail) = state { return detail }
        return throttledDetail
    }

    private static func detail(for error: any Error) -> ErrorDetail {
        switch error {
        case RegistrySearchError.httpStatus(404, _):
            return ErrorDetail(
                title: "Repository not found",
                explanation:
                    "Docker Hub has no repository by that name; it may have been removed.")
        case RegistrySearchError.httpStatus(let code, _):
            return ErrorDetail(
                title: "Docker Hub returned an error",
                explanation: "The request failed with HTTP status \(code). Try again shortly.",
                recoveryActions: [.retry])
        case RegistrySearchError.network(let message):
            return ErrorDetail(
                title: "Couldn't reach Docker Hub",
                explanation: message.isEmpty
                    ? "Check your network connection and try again." : message,
                recoveryActions: [.retry])
        case RegistrySearchError.decodingFailed:
            return ErrorDetail(
                title: "Unexpected response from Docker Hub",
                explanation:
                    "The catalog response couldn't be read; the service may be having trouble.",
                recoveryActions: [.retry])
        default:
            return ErrorDetail(
                title: "Search failed", explanation: String(describing: error),
                recoveryActions: [.retry])
        }
    }

    private struct CacheKey: Hashable {
        var scope: String
        var page: Int
    }

    private struct CacheEntry<Value> {
        var value: Value
        var expires: ContinuousClock.Instant
    }

    private func pruneExpired<Value>(_ cache: inout [CacheKey: CacheEntry<Value>]) {
        let now = ContinuousClock.now
        cache = cache.filter { $0.value.expires > now }
    }
}
