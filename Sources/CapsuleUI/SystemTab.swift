//
//  SystemTab.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

/// The sub-tabs of the always-available System surface. Mirrors the four `TabView` tabs in
/// `SystemDetailView` (Overview / Storage / Service Logs / About) so the palette and menus
/// can deep-link straight to one (`Open System Logs` → `.serviceLogs`,
/// `Reclaim Disk Space` → `.storage`).
public enum SystemTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case storage
    case serviceLogs
    case about

    public var id: String { rawValue }
}
