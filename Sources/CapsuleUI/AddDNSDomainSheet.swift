//
//  AddDNSDomainSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Add a local DNS domain. Collects a domain name and an optional localhost IP, validates
//  them (via the injected model closure), and hands the privileged `system dns create` off to
//  Terminal. The sheet states the administrator requirement up front; it never names a backend
//  Configuration type, never builds argv, and never runs the command in-process.

import CapsuleDomain
import SwiftUI

struct AddDNSDomainSheet: View {
    /// Returns nil on success (handed off to Terminal), or the validation failure to display.
    let onAdd: (DNSDraft) -> ErrorDetail?
    let onClose: () -> Void

    @State private var domain = ""
    @State private var localhostIP = ""
    @State private var failure: ErrorDetail?

    private var trimmedDomain: String {
        domain.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Add DNS Domain", systemImage: "network")
                .font(.headline)

            Form {
                TextField("Domain", text: $domain, prompt: Text("e.g. test"))
                TextField(
                    "Localhost IP (optional)", text: $localhostIP,
                    prompt: Text("e.g. 127.0.0.1"))
            }
            .formStyle(.grouped)

            Label("Requires administrator — opens Terminal.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)

            if let failure {
                VStack(alignment: .leading, spacing: 2) {
                    Label(failure.title, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                    Text(failure.explanation)
                        .font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button("Cancel", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add in Terminal") {
                    let draft = DNSDraft(domain: domain, localhostIP: localhostIP)
                    if let detail = onAdd(draft) {
                        failure = detail
                    } else {
                        onClose()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedDomain.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
