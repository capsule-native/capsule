//
//  ContainerFileEntry.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  One entry in a container's directory listing. apple/container has no file-listing verb,
//  so the adapter derives these from `exec <id> ls -la <path>` (best-effort, lenient).

import Foundation

public struct ContainerFileEntry: Sendable, Equatable, Identifiable {
    public var name: String
    public var isDirectory: Bool
    public var size: Int64?
    public var mode: String?

    public var id: String { name }

    public init(name: String, isDirectory: Bool, size: Int64? = nil, mode: String? = nil) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.mode = mode
    }
}
