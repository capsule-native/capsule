//
//  RegistriesView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Registries preferences pane: lists registry logins, adds one via a login sheet that
//  never echoes secrets, and removes one with a confirmation. Backed by `RegistriesModel`.

import CapsuleDomain
import SwiftUI

struct RegistriesView: View {
    @Bindable var model: RegistriesModel

    @State private var showingLogin = false
    @State private var pendingLogout: Registry?

    init(model: RegistriesModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Registry Logins")
                .font(.headline)
            Text(
                "Credentials are stored by the container runtime. Capsule never displays or "
                    + "logs your password."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            content

            if let notice = model.notice {
                Label(notice.detail.explanation, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Button {
                    showingLogin = true
                } label: {
                    Label("Add Registry…", systemImage: "plus")
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 320, alignment: .topLeading)
        .task { await model.refresh() }
        .sheet(isPresented: $showingLogin) {
            RegistryLoginSheet(
                onLogin: { server, user, pass in
                    let ok = await model.login(server: server, username: user, password: pass)
                    return ok ? nil : model.notice?.detail
                },
                onTest: { server, user, pass in
                    await model.test(server: server, username: user, password: pass)
                },
                onClose: { showingLogin = false },
                invocationFor: { server, user in
                    model.loginInvocation(server: server, username: user)
                })
        }
        .confirmationDialog(
            "Remove the login for \(pendingLogout?.server ?? "")?",
            isPresented: Binding(
                get: { pendingLogout != nil }, set: { if !$0 { pendingLogout = nil } }),
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) {
                if let registry = pendingLogout {
                    pendingLogout = nil
                    Task { await model.logout(server: registry.server) }
                }
            }
            Button("Cancel", role: .cancel) { pendingLogout = nil }
        } message: {
            Text("Pushes and pulls that rely on this registry will need new credentials.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity)
                .accessibilityLabel(Text("Loading", bundle: .module))
        case .unavailable(let detail):
            ContentUnavailableView {
                Label(detail.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(detail.explanation)
            }
        case .loaded:
            if model.registries.isEmpty {
                ContentUnavailableView(
                    "No registry logins", systemImage: "person.badge.key",
                    description: Text("Add a registry to push and pull private images."))
            } else {
                List {
                    ForEach(model.registries) { registry in
                        HStack {
                            Label(registry.server, systemImage: "server.rack")
                            Spacer()
                            Button(role: .destructive) {
                                pendingLogout = registry
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Log out", bundle: .module))
                            .help(Text("Log out of \(registry.server)", bundle: .module))
                        }
                    }
                }
                .frame(minHeight: 160)
            }
        }
    }
}
