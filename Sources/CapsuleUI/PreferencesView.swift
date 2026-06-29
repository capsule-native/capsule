//
//  PreferencesView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The app's Preferences window (⌘,). A tabbed container; today it hosts the Registries
//  pane, with room for future settings panes.

import CapsuleDomain
import SwiftUI

public struct PreferencesView: View {
    private let registriesModel: RegistriesModel
    private let dnsModel: DNSModel
    private let systemHealth: SystemHealth

    public init(
        registriesModel: RegistriesModel,
        dnsModel: DNSModel,
        systemHealth: SystemHealth
    ) {
        self.registriesModel = registriesModel
        self.dnsModel = dnsModel
        self.systemHealth = systemHealth
    }

    public var body: some View {
        TabView {
            RegistriesView(model: registriesModel)
                .tabItem { Label("Registries", systemImage: "person.badge.key") }
            NetworkingView(model: dnsModel)
                .disabled(!systemHealth.supports(.networks))
                .tabItem { Label("Networking", systemImage: "network") }
        }
        .frame(width: 520, height: 420)
    }
}
