//
//  AboutDiagnosticsView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  About/diagnostics pane: component table, OS/app version, compatibility warnings,
//  Copy Bug Report (NSPasteboard), Export Diagnostics (injected onExportDiagnostics).

import CapsuleDomain
import SwiftUI

struct AboutDiagnosticsView: View {
    @Bindable var model: AboutModel
    let onExportDiagnostics: () -> Void

    var body: some View {
        Group {
            if let err = model.loadFailed {
                ContentUnavailableView(
                    "Could not load components",
                    systemImage: "exclamationmark.circle",
                    description: Text(err)
                )
            } else {
                Form {
                    Section("Components") {
                        ForEach(model.components) { c in
                            LabeledContent(c.appName) {
                                VStack(alignment: .trailing) {
                                    Text(c.version).monospaced()
                                    Text("\(c.buildType) · \(c.commit)").font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !model.compatibilityWarnings.isEmpty {
                        Section("Compatibility") {
                            ForEach(model.compatibilityWarnings, id: \.self) { w in
                                Label(w, systemImage: "exclamationmark.triangle").foregroundStyle(
                                    .orange)
                            }
                        }
                    }
                    Section {
                        HStack {
                            Button("Copy Bug Report") {
                                Pasteboard.copy(model.bugReportText)
                            }
                            Button("Export Diagnostics…", action: onExportDiagnostics)
                            Spacer()
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .task { await model.refresh() }
    }
}
