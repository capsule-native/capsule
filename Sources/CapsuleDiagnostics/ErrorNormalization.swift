//
//  ErrorNormalization.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import Foundation

/// Normalizes arbitrary `Error` values into the app's single error currency.
///
/// `CapsuleError` and its presentation (`ErrorDetail`) live in `CapsuleDomain` so the UI
/// can render them; this is the seam that turns *any* raw error — including ones an
/// adapter could not classify — into that currency.
public enum ErrorNormalizer {
    /// Maps any `Error` to a `CapsuleError`.
    ///
    /// A value that is already a `CapsuleError` passes through unchanged; anything else is
    /// wrapped as `.unknown`, preferring a `LocalizedError`'s description when available.
    public static func normalize(_ error: Error) -> CapsuleError {
        if let capsule = error as? CapsuleError {
            return capsule
        }
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return .unknown(message: message)
    }

    /// Maps any `Error` to a presentation-ready `ErrorDetail` with recovery actions.
    public static func detail(for error: Error) -> ErrorDetail {
        normalize(error).detail
    }

    /// A lightweight `DiagnosticInfo` bridge for the simpler `TaskState`/`Outcome` paths.
    public static func diagnosticInfo(for error: Error) -> DiagnosticInfo {
        detail(for: error).diagnosticInfo
    }
}
