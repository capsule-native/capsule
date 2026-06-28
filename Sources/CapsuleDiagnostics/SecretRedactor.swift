//
//  SecretRedactor.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import Foundation

/// Strips credentials from command arguments and free text before they are written into
/// a diagnostic bundle.
///
/// This is defense-in-depth: even when a user opts in to capturing command content, we
/// must *never* persist registry passwords, tokens, or bearer credentials. Redaction is
/// pattern-based and intentionally conservative — it removes the value, keeps the flag, so
/// the transcript still reads sensibly.
public enum SecretRedactor {
    /// The marker substituted in place of a secret value.
    public static let placeholder = "‹redacted›"

    /// Flags whose *following* argument (or `=`-joined value) is a secret.
    private static let secretFlags: Set<String> = [
        "--password", "-p", "--pass", "--passphrase",
        "--token", "--secret",
        "--registry-password", "--registry-token", "--registry-secret",
    ]

    /// Returns a copy of `arguments` with secret-bearing values masked.
    ///
    /// Handles both the space-separated form (`--password hunter2`) and the inline form
    /// (`--password=hunter2`). A dangling secret flag with no value is left untouched.
    public static func redact(arguments: [String]) -> [String] {
        var result: [String] = []
        result.reserveCapacity(arguments.count)
        var redactNext = false

        for argument in arguments {
            if redactNext {
                result.append(placeholder)
                redactNext = false
                continue
            }
            if secretFlags.contains(argument.lowercased()) {
                result.append(argument)
                redactNext = true
                continue
            }
            if argument.hasPrefix("-"), let equals = argument.firstIndex(of: "=") {
                let flag = String(argument[argument.startIndex..<equals])
                if secretFlags.contains(flag.lowercased()) {
                    result.append("\(flag)=\(placeholder)")
                    continue
                }
            }
            result.append(argument)
        }
        return result
    }

    /// Returns `text` with bearer tokens and secret-flag values masked.
    public static func redact(_ text: String) -> String {
        var output = text
        for redaction in redactions {
            output = redaction.apply(to: output)
        }
        return output
    }

    // MARK: - Text patterns

    private struct Redaction {
        let regex: NSRegularExpression
        let template: String

        init(_ pattern: String, _ template: String) {
            // Patterns are compile-time constants; a failure here is a programmer error.
            self.regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            self.template = template
        }

        func apply(to text: String) -> String {
            let range = NSRange(text.startIndex..., in: text)
            return regex.stringByReplacingMatches(
                in: text,
                options: [],
                range: range,
                withTemplate: template
            )
        }
    }

    private static let flagAlternation =
        "--password|--passphrase|--pass|--token|--secret"
        + "|--registry-password|--registry-token|--registry-secret|-p"

    private static let redactions: [Redaction] = [
        // Authorization: Bearer <token>
        Redaction(#"(bearer\s+)\S+"#, "$1\(placeholder)"),
        // --flag=<value>
        Redaction("(\(flagAlternation))=\\S+", "$1=\(placeholder)"),
        // --flag <value>
        Redaction("(\(flagAlternation))(\\s+)\\S+", "$1$2\(placeholder)"),
    ]
}
