//
//  PropertyTOML.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  CapsuleDomain — free of UI / Foundation.Process dependencies.

import Foundation

public struct TOMLIssue: Sendable, Equatable, Identifiable {
    /// Monotonically-increasing index assigned at creation; unique within a single `lint` call.
    public var id: Int
    public var line: Int
    public var message: String
}

/// A deliberately small, lenient linter/parser for the flat `key = value` TOML the
/// `container` config uses (sections, scalar values, `#` comments). Advisory only —
/// Capsule exports config; it never applies it.
public enum PropertyTOML {

    /// Strips a trailing inline `# comment` from a raw value string, respecting
    /// double-quoted strings (a `#` inside quotes is not a comment delimiter).
    /// Returns the stripped, trimmed result.
    private static func stripInlineComment(_ s: String) -> String {
        var inString = false
        var idx = s.startIndex
        while idx < s.endIndex {
            let ch = s[idx]
            if ch == "\"" {
                inString.toggle()
            } else if ch == "#" && !inString {
                return s[..<idx].trimmingCharacters(in: .whitespaces)
            }
            idx = s.index(after: idx)
        }
        return s
    }

    public static func lint(_ text: String) -> [TOMLIssue] {
        var issues: [TOMLIssue] = []
        var inSection = false
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (idx, rawLine) in lines.enumerated() {
            let line = idx + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("[") {
                if !trimmed.hasSuffix("]") {
                    let msg = "Malformed section header."
                    issues.append(TOMLIssue(id: issues.count, line: line, message: msg))
                }
                inSection = true
                continue
            }
            guard let eq = trimmed.firstIndex(of: "=") else {
                let msg = "Expected `key = value`."
                issues.append(TOMLIssue(id: issues.count, line: line, message: msg))
                continue
            }
            if !inSection {
                let msg = "Key is outside any [section]."
                issues.append(TOMLIssue(id: issues.count, line: line, message: msg))
            }
            let rawValue = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let value = stripInlineComment(rawValue)
            if value.isEmpty {
                issues.append(TOMLIssue(id: issues.count, line: line, message: "Missing value."))
            } else if value.hasPrefix("\"") && !(value.count >= 2 && value.hasSuffix("\"")) {
                issues.append(
                    TOMLIssue(id: issues.count, line: line, message: "Unterminated string."))
            }
        }
        return issues
    }

    public static func parse(_ text: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        var section = ""
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let inner = trimmed.dropFirst().dropLast()
                section = String(inner).trimmingCharacters(in: .whitespaces)
                result[section] = result[section] ?? [:]
                continue
            }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            let rawValue = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            var value = stripInlineComment(rawValue)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty { result[section, default: [:]][key] = value }
        }
        return result
    }

    public static func changes(from old: String, to new: String) -> [String] {
        let a = parse(old), b = parse(new)
        var out: [String] = []
        let sections = Set(a.keys).union(b.keys).sorted()
        for s in sections {
            let oldKeys = a[s] ?? [:], newKeys = b[s] ?? [:]
            for k in Set(oldKeys.keys).union(newKeys.keys).sorted() {
                switch (oldKeys[k], newKeys[k]) {
                case let (ov?, nv?) where ov != nv: out.append("\(s).\(k): \(ov) → \(nv)")
                case (nil, let nv?): out.append("\(s).\(k): added (\(nv))")
                case (let ov?, nil): out.append("\(s).\(k): removed (was \(ov))")
                default: break
                }
            }
        }
        return out
    }
}
