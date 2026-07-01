//
//  PropertiesEditorSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  A modal TOML editor for system properties: monospaced TextEditor, live lint issues,
//  change-review disclosure, Export via NSSavePanel, and a restart-required banner.

import AppKit  // NSSavePanel
import CapsuleDomain
import SwiftUI
import UniformTypeIdentifiers

struct PropertiesEditorSheet: View {
    @Bindable var model: SystemPropertiesModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit Configuration (TOML)").font(.title3.bold())
            if let err = model.loadError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8).background(CapsuleColors.softFill(.red, contrast: contrast))
            }
            if model.requiresRestart { restartBanner }
            TextEditor(text: $model.editBuffer)
                .font(.body.monospaced()).frame(minWidth: 560, minHeight: 320)
                .border(.quaternary)
            if !model.issues.isEmpty {
                ForEach(model.issues) { issue in
                    Label("Line \(issue.line): \(issue.message)", systemImage: "xmark.octagon")
                        .foregroundStyle(.red).font(.caption)
                }
            }
            if !model.changeReview.isEmpty {
                DisclosureGroup("Change review (\(model.changeReview.count))") {
                    ForEach(model.changeReview, id: \.self) { Text($0).font(.caption.monospaced()) }
                }
            }
            HStack {
                Button("Revert") { model.resetEdits() }.disabled(!model.isDirty)
                Spacer()
                Button("Export…") { export() }
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 640, height: 560)
        .alert(
            "Export Failed",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var restartBanner: some View {
        Label(model.restartBannerMessage, systemImage: "arrow.clockwise.circle")
            .foregroundStyle(.orange).font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8).background(CapsuleColors.softFill(.orange, contrast: contrast))
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "container-config.toml"
        if let toml = UTType(filenameExtension: "toml") { panel.allowedContentTypes = [toml] }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try model.exportText.write(to: url, atomically: true, encoding: .utf8)
                model.markExported()
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}
