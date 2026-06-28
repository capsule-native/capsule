//
//  SemanticVersion.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// A `major.minor.patch` version, tolerant of noisy surrounding text so it can be lifted
/// out of strings like `"container-apiserver version 1.0.0 (build: release)"`.
public struct SemanticVersion: Sendable, Equatable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Extracts the first `\d+.\d+(.\d+)?` run from `string`; a missing patch defaults
    /// to `0`. Returns `nil` when no version-like substring is present.
    public init?(parsing string: String) {
        guard let range = string.range(of: #"\d+\.\d+(\.\d+)?"#, options: .regularExpression)
        else { return nil }
        let numbers = string[range].split(separator: ".").compactMap { Int($0) }
        guard numbers.count >= 2 else { return nil }
        self.init(numbers[0], numbers[1], numbers.count > 2 ? numbers[2] : 0)
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
