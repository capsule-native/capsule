//
//  RegistryLoginSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Log in to a registry. The password is entered in a `SecureField` and is never echoed,
//  stored, or logged. A Test action validates credentials before committing, and any
//  auth/registry failure is shown verbatim so the user can act on it.

import CapsuleDomain
import SwiftUI

struct RegistryLoginSheet: View {
    /// Returns nil on success, or the failure detail to display.
    let onLogin: (String, String?, String?) async -> ErrorDetail?
    let onTest: (String, String?, String?) async -> RegistryTestResult
    let onClose: () -> Void

    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var testResult: RegistryTestResult?
    @State private var failure: ErrorDetail?

    private var trimmedServer: String {
        server.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var credentials: (String?, String?) {
        (
            username.isEmpty ? nil : username,
            password.isEmpty ? nil : password
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Registry Login", systemImage: "person.badge.key")
                .font(.headline)

            Form {
                TextField("Server", text: $server, prompt: Text("e.g. ghcr.io"))
                TextField("Username (optional)", text: $username)
                SecureField("Password", text: $password)
            }
            .formStyle(.grouped)

            if let testResult {
                switch testResult {
                case .success:
                    Label("Credentials are valid.", systemImage: "checkmark.seal")
                        .font(.callout).foregroundStyle(.green)
                case let .failure(detail):
                    failureLabel(detail)
                }
            }
            if let failure {
                failureLabel(failure)
            }

            HStack {
                Button("Cancel", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Test") {
                    let (user, pass) = credentials
                    Task {
                        busy = true
                        failure = nil
                        testResult = await onTest(trimmedServer, user, pass)
                        busy = false
                    }
                }
                .disabled(trimmedServer.isEmpty || busy)
                Spacer()
                Button("Log In") {
                    let (user, pass) = credentials
                    Task {
                        busy = true
                        testResult = nil
                        if let detail = await onLogin(trimmedServer, user, pass) {
                            failure = detail
                        } else {
                            onClose()
                        }
                        busy = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedServer.isEmpty || busy)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func failureLabel(_ detail: ErrorDetail) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(detail.title, systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
            Text(detail.explanation)
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
