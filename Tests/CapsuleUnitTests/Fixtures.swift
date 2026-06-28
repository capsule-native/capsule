//
//  Fixtures.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Loads the real `container ... --format json` captures bundled with the unit
//  test target. These let us prove the decoders against genuine CLI output without
//  ever spawning the `container` binary, keeping the suite hermetic in CI.

import Foundation
import XCTest

enum Fixture {
    /// Returns the raw bytes of a bundled JSON fixture, failing the test if absent.
    static func data(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> Data {
        guard
            let url = Bundle.module.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "Fixtures"
            )
        else {
            XCTFail("Missing fixture: \(name).json", file: file, line: line)
            return Data()
        }
        // swiftlint:disable:next force_try
        return (try? Data(contentsOf: url)) ?? Data()
    }

    /// Returns the fixture decoded as a UTF-8 string.
    static func text(_ name: String) -> String {
        String(decoding: data(name), as: UTF8.self)
    }
}
