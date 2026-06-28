//
//  ShellActions.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import Foundation

/// The action callbacks the shell hands to its subviews, in one bag so views take a
/// single dependency rather than a fistful of closures.
///
/// `recover` dispatches any ``RecoveryAction`` (Start Services, Open Logs, Export
/// Diagnostics, Try Again, …). `stopServices` is separate because stopping the service is
/// a deliberate user action, not the remedy for an error, so it has no `RecoveryAction`.
@MainActor
public struct ShellActions {
    public var recover: (RecoveryAction) -> Void
    public var stopServices: () -> Void

    public init(
        recover: @escaping (RecoveryAction) -> Void,
        stopServices: @escaping () -> Void
    ) {
        self.recover = recover
        self.stopServices = stopServices
    }
}
