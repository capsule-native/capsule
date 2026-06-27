//
//  ArgumentBuilder.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// Builds an `argv` array for the container CLI.
///
/// Pure and value-typed, so command construction is trivially unit-testable without
/// spawning any process.
public struct ArgumentBuilder: Sendable, Equatable {
    public private(set) var arguments: [String]

    public init(_ subcommand: String...) {
        self.arguments = subcommand
    }

    /// Appends positional arguments.
    public func adding(_ args: String...) -> ArgumentBuilder {
        var copy = self
        copy.arguments.append(contentsOf: args)
        return copy
    }

    /// Appends `name value` only when `value` is non-nil.
    public func flag(_ name: String, _ value: String?) -> ArgumentBuilder {
        guard let value else { return self }
        var copy = self
        copy.arguments.append(contentsOf: [name, value])
        return copy
    }

    /// Appends a boolean switch (e.g. `--all`) only when `enabled`.
    public func option(_ name: String, enabled: Bool) -> ArgumentBuilder {
        guard enabled else { return self }
        var copy = self
        copy.arguments.append(name)
        return copy
    }
}
