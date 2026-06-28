//
//  SystemDetailView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The "System" section's content: version readout, the live run state, and the explicit
//  Start / Stop Services controls. Always reachable, even when nothing else is.

import CapsuleDomain
import SwiftUI

struct SystemDetailView: View {
    let health: SystemHealth
    let actions: ShellActions

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Service") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(CapsuleColors.accent(for: health.bannerKind))
                            .frame(width: 8, height: 8)
                        Text(statusLabel)
                    }
                }
                if case let .running(version, _) = health {
                    LabeledContent("CLI", value: version.client)
                    LabeledContent("Service", value: version.server ?? "—")
                }
            }

            Section {
                HStack(spacing: 10) {
                    Button("Start Services") { actions.recover(.startServices) }
                        .buttonStyle(.borderedProminent)
                        .disabled(health.isRunning)
                    Button("Stop Services") { actions.stopServices() }
                        .buttonStyle(.bordered)
                        .disabled(!health.isRunning)
                    Spacer()
                    Button("Export Diagnostics…") { actions.recover(.exportDiagnostics) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var statusLabel: String {
        switch health {
        case .unknown, .checking: return "Checking…"
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .unavailable: return "Unavailable"
        }
    }
}
