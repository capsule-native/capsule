//
//  LifecycleNoticeView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Renders a `LifecycleNotice` (info or recoverable error) with its recovery actions. The
//  `.retry` action is container-scoped — the caller supplies the closures, so it never
//  routes to the shell's generic system refresh.

import CapsuleDomain
import SwiftUI

struct LifecycleNoticeView: View {
    let notice: LifecycleNotice
    let onAction: (RecoveryAction) -> Void
    let onForceStop: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(notice.detail.title).font(.headline)
                Text(notice.detail.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if notice.offersShellHint {
                    Text("Open a shell from the read-only console to investigate.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 10) {
                    if let id = notice.forceStopID {
                        Button("Force Stop", role: .destructive) { onForceStop(id) }
                            .buttonStyle(.borderedProminent)
                    }
                    if !notice.detail.recoveryActions.isEmpty {
                        RecoveryActionButtons(
                            actions: notice.detail.recoveryActions, onRecover: onAction)
                    }
                }
                .padding(.top, 2)
            }
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }
}
