//
//  OutputLine.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// A single incremental line emitted by a long-running backend command (build, pull,
/// push, `logs --follow`). Carries which stream it came from so a console view can
/// distinguish progress from diagnostics.
public struct OutputLine: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case stdout
        case stderr
    }

    public let source: Source
    public let text: String

    public init(source: Source, text: String) {
        self.source = source
        self.text = text
    }
}
