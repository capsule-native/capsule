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

    public init(registriesModel: RegistriesModel) {
        self.registriesModel = registriesModel
    }

    public var body: some View {
        TabView {
            RegistriesView(model: registriesModel)
                .tabItem { Label("Registries", systemImage: "person.badge.key") }
        }
        .frame(width: 520, height: 420)
    }
}
