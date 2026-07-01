//
//  AdvancedDisclosure.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The single "common controls visible / advanced flags behind disclosure" wrapper, adopted
//  across the Create/Run/Build/Copy sheets so the tiered-complexity stacking order is uniform:
//  common control → advanced disclosure → raw preview → terminal fallback. Self-manages its
//  expansion unless a caller supplies an `isExpanded` binding.
//

import SwiftUI

struct AdvancedDisclosure<Content: View>: View {
    private let title: String
    private let externalExpansion: Binding<Bool>?
    @State private var internalExpansion = false
    private let content: Content

    init(
        _ title: String = "Advanced",
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.externalExpansion = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(title, isExpanded: externalExpansion ?? $internalExpansion) {
            content
        }
    }
}
