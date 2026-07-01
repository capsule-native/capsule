//
//  CommandPreviewView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The one "Command preview" block, shared by every task sheet and the post-run transcript.
//  Shows the redacted `displayString` monospaced + selectable, a Copy button (copies the
//  redacted string), and — when an escalation handler is supplied — an Open-in-Terminal
//  button that hands back the (raw-argv-carrying) invocation. Replaces ~5 copy-pasted blocks.
//

import CapsuleDomain
import SwiftUI

struct CommandPreviewView: View {
    private let invocation: CommandInvocation
    private let onEscalate: ((CommandInvocation) -> Void)?

    init(_ invocation: CommandInvocation, onEscalate: ((CommandInvocation) -> Void)? = nil) {
        self.invocation = invocation
        self.onEscalate = onEscalate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Command preview").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 8) {
                Text(invocation.displayString)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(CapsuleColors.activitySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(spacing: 6) {
                    Button {
                        Pasteboard.copy(invocation.displayString)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy command")
                    .accessibilityLabel(Text("Copy command", bundle: .module))
                    if let onEscalate {
                        Button {
                            onEscalate(invocation)
                        } label: {
                            Image(systemName: "terminal")
                        }
                        .buttonStyle(.borderless)
                        .help("Open in Terminal")
                        .accessibilityLabel(Text("Open in Terminal", bundle: .module))
                    }
                }
            }
        }
    }
}
