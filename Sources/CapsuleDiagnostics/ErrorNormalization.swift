//
//  ErrorNormalization.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import Foundation

/// Maps arbitrary `Error` values into the domain's presentable `DiagnosticInfo`.
public enum ErrorNormalizer {
    public static func normalize(
        _ error: Error,
        summary: String = "Operation failed"
    ) -> DiagnosticInfo {
        let detail = (error as? LocalizedError)?.errorDescription
        return DiagnosticInfo(
            summary: summary,
            detail: detail,
            underlyingDescription: String(describing: error)
        )
    }
}
