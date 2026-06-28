//
//  ProgressParser.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Best-effort determinate progress: when a streamed CLI line carries a clean `NN%`, the
//  task center promotes the task to determinate progress; otherwise progress stays nil
//  (indeterminate) and the transcript remains the source of truth. Pure — no Process, no UI.

import Foundation

public enum ProgressParser {
    /// Extracts a `0.0...1.0` fraction from the last `NN%` token in `line`, or nil when the
    /// line carries no percentage. The last match wins so a line like `"a 10% b 80%"` reports
    /// the most recent figure; values are clamped to `0...100`.
    public static func fraction(in line: String) -> Double? {
        let scalars = Array(line.unicodeScalars)
        var lastPercent: Int?
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "%" else {
                index += 1
                continue
            }
            // Walk backwards over up to three digits immediately preceding the '%'.
            var digitsEnd = index
            var digitsStart = index
            while digitsStart > 0, scalars[digitsStart - 1].properties.numericType == .decimal,
                index - digitsStart < 3
            {
                digitsStart -= 1
            }
            if digitsStart < digitsEnd {
                let digits = String(String.UnicodeScalarView(scalars[digitsStart..<digitsEnd]))
                if let value = Int(digits) {
                    lastPercent = value
                }
            }
            index += 1
        }
        guard let percent = lastPercent else { return nil }
        return Double(min(max(percent, 0), 100)) / 100.0
    }
}
