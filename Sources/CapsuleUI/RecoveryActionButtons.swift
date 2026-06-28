//
//  RecoveryActionButtons.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import SwiftUI

/// A row of recovery-action buttons. The first action is emphasized (it is the primary
/// remedy — typically Start Services or Try Again); the rest are plain.
struct RecoveryActionButtons: View {
    let actions: [RecoveryAction]
    let onRecover: (RecoveryAction) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                button(for: action, emphasized: index == 0)
            }
        }
    }

    @ViewBuilder
    private func button(for action: RecoveryAction, emphasized: Bool) -> some View {
        if emphasized {
            Button(action.title) { onRecover(action) }
                .buttonStyle(.borderedProminent)
        } else {
            Button(action.title) { onRecover(action) }
                .buttonStyle(.bordered)
        }
    }
}
