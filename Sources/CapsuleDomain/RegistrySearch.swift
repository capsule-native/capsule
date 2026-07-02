//
//  RegistrySearch.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Domain models
//  for browsing a registry's public catalog — repositories and tags as the UI renders
//  them, mapped from the backend port's summaries so wire shapes never reach the UI.

import CapsuleBackend
import Foundation

/// One repository hit in a registry catalog search.
public struct RegistryRepository: Sendable, Equatable, Identifiable {
    public var name: String
    public var shortDescription: String?
    public var starCount: Int?
    public var pullCount: Int64?
    public var isOfficial: Bool

    public var id: String { name }

    public init(
        name: String, shortDescription: String? = nil, starCount: Int? = nil,
        pullCount: Int64? = nil, isOfficial: Bool = false
    ) {
        self.name = name
        self.shortDescription = shortDescription
        self.starCount = starCount
        self.pullCount = pullCount
        self.isOfficial = isOfficial
    }

    /// Maps a backend summary into the domain model.
    public init(summary: RegistryRepositorySummary) {
        self.init(
            name: summary.name,
            shortDescription: summary.shortDescription,
            starCount: summary.starCount,
            pullCount: summary.pullCount,
            isOfficial: summary.isOfficial
        )
    }

    /// The repository path as the registry's API addresses it: official images live in
    /// the implicit `library` namespace ("nginx" → "library/nginx").
    public var namespacedName: String {
        name.contains("/") ? name : "library/\(name)"
    }

    /// The fully-qualified pull reference for one of this repository's tags, e.g.
    /// `docker.io/library/nginx:1.27` — exactly what the existing pull path expects.
    public func pullReference(tag: String) -> String {
        "docker.io/\(namespacedName):\(tag)"
    }
}

/// One tag of a repository, with its parsed last-update timestamp.
public struct RegistryTag: Sendable, Equatable, Identifiable {
    public var name: String
    public var lastUpdated: Date?
    public var sizeBytes: Int64?

    public var id: String { name }

    public init(name: String, lastUpdated: Date? = nil, sizeBytes: Int64? = nil) {
        self.name = name
        self.lastUpdated = lastUpdated
        self.sizeBytes = sizeBytes
    }

    /// Maps a backend summary into the domain model, parsing the ISO-8601 timestamp.
    public init(summary: RegistryTagSummary) {
        self.init(
            name: summary.name,
            lastUpdated: summary.lastUpdated.flatMap(Container.parseDate),
            sizeBytes: summary.sizeBytes
        )
    }
}
