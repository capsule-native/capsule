//
//  PropertyTOML.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  CapsuleDomain — free of UI / Foundation.Process dependencies.

import Foundation

public struct TOMLIssue: Sendable, Equatable, Identifiable {
    public var line: Int
    public var message: String
    public var id: Int { line }
}

/// A deliberately small, lenient linter/parser for the flat `key = value` TOML the
/// `container` config uses (sections, scalar values, `#` comments). Advisory only —
/// Capsule exports config; it never applies it.
public enum PropertyTOML {
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
                    issues.append(TOMLIssue(line: line, message: "Malformed section header."))
                }
                inSection = true
                continue
            }
            guard let eq = trimmed.firstIndex(of: "=") else {
                issues.append(TOMLIssue(line: line, message: "Expected `key = value`."))
                continue
            }
            if !inSection {
                issues.append(TOMLIssue(line: line, message: "Key is outside any [section]."))
            }
            let value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                issues.append(TOMLIssue(line: line, message: "Missing value."))
            } else if value.hasPrefix("\"") && !(value.count >= 2 && value.hasSuffix("\"")) {
                issues.append(TOMLIssue(line: line, message: "Unterminated string."))
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
            var value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
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
