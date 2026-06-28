//
//  CommandTokenizer.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Splits a user-typed command string into argv tokens, honoring single/double quotes so
//  `sh -c "echo hi"` becomes ["sh", "-c", "echo hi"]. Pure; shared by Run and Exec.

import Foundation

public enum CommandTokenizer {
    public static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var hasToken = false

        for character in input {
            if let active = quote {
                if character == active {
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
                hasToken = true
            } else if character == " " || character == "\t" {
                if hasToken {
                    tokens.append(current)
                    current = ""
                    hasToken = false
                }
            } else {
                current.append(character)
                hasToken = true
            }
        }
        if hasToken { tokens.append(current) }
        return tokens
    }
}
