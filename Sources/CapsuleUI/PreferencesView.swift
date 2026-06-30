//
//  PreferencesView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The app's Preferences window (⌘,). A tabbed container hosting General, Registries,
//  Networking, and Advanced (kernel) panes.

import CapsuleDomain
import SwiftUI

public struct PreferencesView: View {
    private let registriesModel: RegistriesModel
    private let dnsModel: DNSModel
    private let kernelModel: KernelManagerModel
    private let propertiesModel: SystemPropertiesModel
    private let systemHealth: SystemHealth

    public init(
        registriesModel: RegistriesModel,
        dnsModel: DNSModel,
        kernelModel: KernelManagerModel,
        propertiesModel: SystemPropertiesModel,
        systemHealth: SystemHealth
    ) {
        self.registriesModel = registriesModel
        self.dnsModel = dnsModel
        self.kernelModel = kernelModel
        self.propertiesModel = propertiesModel
        self.systemHealth = systemHealth
    }

    public var body: some View {
        TabView {
            TerminalPreferenceView()
                .tabItem { Label("General", systemImage: "gearshape") }
            RegistriesView(model: registriesModel)
                .tabItem { Label("Registries", systemImage: "person.badge.key") }
            NetworkingView(model: dnsModel)
                .disabled(!systemHealth.supports(.networks))
                .tabItem { Label("Networking", systemImage: "network") }
            AdvancedSettingsView(kernelModel: kernelModel, propertiesModel: propertiesModel)
                .disabled(!systemHealth.supports(.system))
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 520, height: 420)
    }
}
