//
//  FuzzyMatch.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. A pure,
//  case-insensitive subsequence matcher used to rank command-palette entries — kept in
//  Domain so it is unit-testable without any SwiftUI surface.

/// Case-insensitive subsequence fuzzy matching for the command palette.
public enum FuzzyMatch {
    /// Whether every character of `query` appears in `candidate`, in order.
    public static func matches(_ query: String, _ candidate: String) -> Bool {
        score(query, candidate) != nil
    }

    /// A match score (lower is better), or nil when `query` is not a subsequence of
    /// `candidate`. Earlier and more contiguous matches score lower.
    public static func score(_ query: String, _ candidate: String) -> Int? {
        let needle = Array(query.lowercased())
        guard !needle.isEmpty else { return 0 }
        let haystack = Array(candidate.lowercased())

        var qi = 0
        var total = 0
        var lastMatch = -1
        for (ci, ch) in haystack.enumerated() where qi < needle.count && ch == needle[qi] {
            // Distance from the start for the first hit; gap since the previous hit otherwise.
            total += lastMatch < 0 ? ci : (ci - lastMatch - 1)
            lastMatch = ci
            qi += 1
        }
        return qi == needle.count ? total : nil
    }
}
