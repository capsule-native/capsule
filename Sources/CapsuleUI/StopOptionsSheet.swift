//
//  StopOptionsSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Exposes the graceful-stop options (timeout + signal) and maps them to a `StopOptions`.

import SwiftUI

struct StopOptionsSheet: View {
    let containerName: String
    let onStop: (_ timeout: Int, _ signal: String) -> Void
    let onCancel: () -> Void

    @State private var timeout = 5
    @State private var signal = "TERM"

    private let signals = ["TERM", "INT", "QUIT", "HUP"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stop “\(containerName)”")
                .font(.headline)

            Form {
                Stepper(value: $timeout, in: 0...120) {
                    LabeledContent("Timeout", value: "\(timeout) s")
                }
                Picker("Signal", selection: $signal) {
                    ForEach(signals, id: \.self) { Text($0).tag($0) }
                }
            }
            .formStyle(.grouped)

            Text("Sends the signal, then force-stops after the timeout.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Stop") { onStop(timeout, signal) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
