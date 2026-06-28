//
//  CapsuleColors.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Semantic colors for the shell. Everything is derived from system colors so light and
//  dark are correct for free, and every value takes a `ColorSchemeContrast` so that with
//  "Increase contrast" enabled the tints deepen and borders strengthen rather than
//  staying washed out.

import CapsuleDomain
import SwiftUI

public enum CapsuleColors {
    /// The defining accent for a banner state — the color of its status dot and border.
    public static func accent(for kind: BannerKind) -> Color {
        switch kind {
        case .healthy: return .green
        case .caution: return .orange
        case .unhealthy: return .red
        case .info: return .secondary
        }
    }

    /// A soft fill behind a banner; deepens under increased contrast.
    public static func bannerBackground(
        _ kind: BannerKind, contrast: ColorSchemeContrast
    ) -> Color {
        accent(for: kind).opacity(contrast == .increased ? 0.28 : 0.14)
    }

    /// The banner's border; nearly invisible normally, assertive under increased contrast.
    public static func bannerBorder(_ kind: BannerKind, contrast: ColorSchemeContrast) -> Color {
        accent(for: kind).opacity(contrast == .increased ? 0.9 : 0.35)
    }

    /// Primary text on a banner — always the system label color for maximum legibility.
    public static var bannerForeground: Color { .primary }

    /// The surface behind the bottom Activity pane.
    public static var activitySurface: Color {
        Color(nsColor: .underPageBackgroundColor)
    }
}
