//
//  NetworkingView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Networking preferences pane: lists the configured local DNS domains and adds/removes
//  them. DNS changes always require administrator rights, so Add and Delete hand off to a
//  sudo Terminal session rather than running in-process. Backed by `DNSModel`.

import CapsuleDomain
import SwiftUI

struct NetworkingView: View {
    @Bindable var model: DNSModel

    @State private var showingAdd = false
    @State private var pendingDelete: DNSDomain?
    @State private var handedOff = false

    init(model: DNSModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local DNS Domains")
                .font(.headline)
            Text(
                "Resolve container names under a local domain. Creating or removing a domain "
                    + "requires administrator rights and opens Terminal."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            content

            if handedOff {
                Label(
                    "Complete the operation in Terminal, then Refresh.", systemImage: "terminal"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            if let notice = model.notice {
                Label(notice.detail.explanation, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Domain…", systemImage: "plus")
                }
                Button {
                    handedOff = false
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 320, alignment: .topLeading)
        .task { await model.refresh() }
        .sheet(isPresented: $showingAdd) {
            AddDNSDomainSheet(
                onAdd: { draft in
                    switch model.addDomain(draft) {
                    case .success:
                        handedOff = true
                        return nil
                    case let .failure(error):
                        return error.detail
                    }
                },
                onClose: { showingAdd = false })
        }
        .confirmationDialog(
            "Delete DNS domain \(pendingDelete?.domain ?? "")?",
            isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete in Terminal", role: .destructive) {
                if let domain = pendingDelete {
                    pendingDelete = nil
                    model.deleteDomain(domain.domain)
                    handedOff = true
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Requires administrator — opens Terminal to remove the domain.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity)
        case let .unavailable(detail):
            ContentUnavailableView {
                Label(detail.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(detail.explanation)
            }
        case .loaded:
            if model.domains.isEmpty {
                ContentUnavailableView(
                    "No local DNS domains", systemImage: "network",
                    description: Text("Add a domain to resolve container names locally."))
            } else {
                List {
                    ForEach(model.domains) { domain in
                        HStack {
                            VStack(alignment: .leading) {
                                Label(domain.domain, systemImage: "network")
                                if let ip = domain.localhostIP {
                                    Text("localhost → \(ip)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                pendingDelete = domain
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete \(domain.domain) (requires administrator)")
                        }
                    }
                }
                .frame(minHeight: 160)
            }
        }
    }
}
