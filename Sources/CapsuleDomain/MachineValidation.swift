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
}
