//
//  CIDR.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. CIDR parsing and
//  overlap detection are pure value computations used by network subnet-conflict validation.

import Foundation

/// Minimal CIDR support for subnet-conflict detection: parse an IPv4/IPv6 `address/prefix`
/// string into network-address bytes, and test whether two CIDR blocks overlap.
public enum CIDR {
    /// A parsed CIDR block: the raw network-address bytes (4 for IPv4, 16 for IPv6) and the
    /// prefix length, with the family flagged for fast same-family checks.
    public struct Parsed: Sendable, Equatable {
        public var bytes: [UInt8]
        public var prefixLength: Int
        public var isIPv6: Bool

        public init(bytes: [UInt8], prefixLength: Int, isIPv6: Bool) {
            self.bytes = bytes
            self.prefixLength = prefixLength
            self.isIPv6 = isIPv6
        }
    }

    /// Parses `"<address>/<prefix>"`, returning `nil` for anything malformed (missing or
    /// non-numeric prefix, out-of-range prefix, or an unparseable address).
    public static func parse(_ text: String) -> Parsed? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let prefix = Int(parts[1]) else { return nil }
        let address = String(parts[0])

        if let bytes = parseIPv4(address) {
            guard prefix >= 0, prefix <= 32 else { return nil }
            return Parsed(bytes: bytes, prefixLength: prefix, isIPv6: false)
        }
        if let bytes = parseIPv6(address) {
            guard prefix >= 0, prefix <= 128 else { return nil }
            return Parsed(bytes: bytes, prefixLength: prefix, isIPv6: true)
        }
        return nil
    }

    // MARK: - Address parsing

    private static func parseIPv4(_ text: String) -> [UInt8]? {
        let octets = text.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return nil }
        var bytes: [UInt8] = []
        for octet in octets {
            guard let value = Int(octet), value >= 0, value <= 255 else { return nil }
            bytes.append(UInt8(value))
        }
        return bytes
    }

    private static func parseIPv6(_ text: String) -> [UInt8]? {
        let halves = text.components(separatedBy: "::")
        guard halves.count <= 2 else { return nil }

        func groups(_ part: String) -> [UInt16]? {
            if part.isEmpty { return [] }
            var result: [UInt16] = []
            for segment in part.split(separator: ":", omittingEmptySubsequences: false) {
                guard !segment.isEmpty, segment.count <= 4,
                    let value = UInt16(segment, radix: 16)
                else { return nil }
                result.append(value)
            }
            return result
        }

        let all: [UInt16]
        if halves.count == 2 {
            guard let head = groups(halves[0]), let tail = groups(halves[1]) else { return nil }
            let missing = 8 - (head.count + tail.count)
            guard missing >= 1 else { return nil }
            all = head + Array(repeating: 0, count: missing) + tail
        } else {
            guard let whole = groups(text), whole.count == 8 else { return nil }
            all = whole
        }

        var bytes: [UInt8] = []
        for group in all {
            bytes.append(UInt8(group >> 8))
            bytes.append(UInt8(group & 0xff))
        }
        return bytes
    }
}

extension CIDR {
    /// Whether two CIDR blocks share any address. Returns `false` when the families differ
    /// or either string is malformed, so a bad input never reports a phantom conflict.
    public static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        guard let a = parse(lhs), let b = parse(rhs), a.isIPv6 == b.isIPv6 else { return false }
        return sameNetwork(a.bytes, b.bytes, prefixBits: min(a.prefixLength, b.prefixLength))
    }

    /// Compares two equal-length address byte arrays over the leading `prefixBits` bits.
    private static func sameNetwork(_ a: [UInt8], _ b: [UInt8], prefixBits: Int) -> Bool {
        guard a.count == b.count else { return false }
        let fullBytes = prefixBits / 8
        let remainingBits = prefixBits % 8
        for index in 0..<fullBytes where a[index] != b[index] { return false }
        if remainingBits > 0 {
            let mask = UInt8(truncatingIfNeeded: 0xFF << (8 - remainingBits))
            if (a[fullBytes] & mask) != (b[fullBytes] & mask) { return false }
        }
        return true
    }
}
