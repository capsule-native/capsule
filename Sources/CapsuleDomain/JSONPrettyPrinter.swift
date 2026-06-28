//
//  JSONPrettyPrinter.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`.

import Foundation

/// Formats a raw JSON string for display, falling back to the unmodified input when the
/// payload is not valid JSON — so a CLI schema drift degrades to "show the raw text"
/// rather than an empty inspector.
public enum JSONPrettyPrinter {
    public static func prettyPrint(_ raw: String) -> String {
        guard
            let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: pretty, encoding: .utf8)
        else {
            return raw
        }
        return string
    }
}
