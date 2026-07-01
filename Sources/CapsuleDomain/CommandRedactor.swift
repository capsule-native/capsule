//
//  CommandRedactor.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Operation-aware redaction for command previews. Unlike SecretRedactor (which lives in
//  CapsuleDiagnostics and masks -p), this Domain-local policy NEVER masks -p/--publish, so
//  `container run -p 8080:80` previews faithfully. The real argv handed to the runner /
//  terminal is always unredacted; only the on-screen / copy form passes through here.

import Foundation

public enum CommandRedactor {
    /// Replacement token shown in place of a masked secret value.
    public static let placeholder = "‹redacted›"

    /// Flags whose immediately-following token is a bare secret to mask.
    private static let secretFlags: Set<String> =
        ["--password", "--passphrase", "--token", "--secret"]

    /// Flags whose argument is a `KEY=VALUE` entry; mask VALUE only when KEY looks sensitive.
    private static let keyValueFlags: Set<String> = ["-e", "--env", "--build-arg"]

    /// Case-insensitive KEY fragments that mark a `KEY=VALUE` entry's value as sensitive.
    private static let sensitiveKeyFragments = ["pass", "secret", "token", "key", "cred"]

    /// Returns `arguments` with secret values replaced by `placeholder`.
    ///
    /// Policy: mask the token after a secret flag and the `=value` form of those flags; mask
    /// the value portion of an `-e`/`--env`/`--build-arg` entry whose key matches a sensitive
    /// fragment. `-p`/`--publish` is never touched.
    public static func redactedArguments(_ arguments: [String]) -> [String] {
        var result: [String] = []
        result.reserveCapacity(arguments.count)
        var index = 0
        while index < arguments.count {
            let token = arguments[index]

            // `--password value` → mask the NEXT token.
            if secretFlags.contains(token), index + 1 < arguments.count {
                result.append(token)
                result.append(placeholder)
                index += 2
                continue
            }

            // `--password=value` → mask everything after the first `=`.
            if let eq = token.firstIndex(of: "="),
                secretFlags.contains(String(token[token.startIndex..<eq]))
            {
                result.append(String(token[token.startIndex...eq]) + placeholder)
                index += 1
                continue
            }

            // `-e KEY=secret` / `--env …` / `--build-arg …` → mask VALUE iff KEY is sensitive.
            if keyValueFlags.contains(token), index + 1 < arguments.count {
                result.append(token)
                result.append(redactedKeyValueEntry(arguments[index + 1]))
                index += 2
                continue
            }

            result.append(token)
            index += 1
        }
        return result
    }

    /// Masks the value of a `KEY=VALUE` entry when KEY matches a sensitive fragment; otherwise
    /// returns the entry unchanged (including entries that have no `=`).
    private static func redactedKeyValueEntry(_ entry: String) -> String {
        guard let eq = entry.firstIndex(of: "=") else { return entry }
        let key = entry[entry.startIndex..<eq].lowercased()
        guard sensitiveKeyFragments.contains(where: { key.contains($0) }) else { return entry }
        return String(entry[entry.startIndex...eq]) + placeholder
    }
}
