//
//  MachineValidation.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

public enum MachineValidation {
    public static func imageProblem(_ image: String) -> String? {
        image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "An image reference is required (e.g. alpine:3.22)." : nil
    }
    public static func cpusProblem(_ cpus: String) -> String? {
        let t = cpus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        guard let n = Int(t), n > 0 else { return "CPUs must be a positive whole number." }
        return nil
    }
    public static func memoryProblem(_ memory: String) -> String? {
        let t = memory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return t.range(of: #"^\d+(\.\d+)?[MmGg]$"#, options: .regularExpression) != nil
            ? nil : "Memory must be a size like 2G or 512M."
    }
    public static func homeMountProblem(_ value: String) -> String? {
        ["rw", "ro", "none"].contains(value.lowercased())
            ? nil : "Home mount must be rw, ro, or none."
    }

    /// Derives a CLI-valid machine name from an image reference, for when the user leaves the
    /// name blank. Machine names allow only lowercase letters, digits, and hyphens, starting and
    /// ending with an alphanumeric. e.g. "alpine:3.22" -> "alpine-3-22",
    /// "docker.io/library/ubuntu:24.04" -> "ubuntu-24-04".
    public static func derivedName(fromImage image: String) -> String {
        let last = image.split(separator: "/").last.map(String.init) ?? image
        let lowered = last.lowercased()
        var s = String(
            lowered.map { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") ? $0 : "-" })
        while s.contains("--") { s = s.replacingOccurrences(of: "--", with: "-") }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return s.isEmpty ? "machine" : s
    }

    /// Validates a user-typed machine name (empty is OK — it will be derived from the image).
    public static func nameProblem(_ name: String) -> String? {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.range(of: #"^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"#, options: .regularExpression) == nil {
            return
                "Name must be lowercase letters, digits, or hyphens, and start and end with a letter or digit."
        }
        return nil
    }
}
