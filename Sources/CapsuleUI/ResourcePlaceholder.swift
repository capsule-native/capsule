//
//  ResourcePlaceholder.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import SwiftUI

/// Detail-pane placeholder shown until real inspectors land in later milestones.
struct ResourcePlaceholder: View {
    let state: TaskState

    var body: some View {
        ContentUnavailableView {
            Label("No Selection", systemImage: "shippingbox")
        } description: {
            Text(statusText)
        }
    }

    private var statusText: String {
        switch state {
        case .idle: return "Idle"
        case .queued: return "Queued…"
        case .running: return "Loading…"
        case .succeeded: return "Select a resource to inspect"
        case .failed(let info): return info.summary
        }
    }
}
