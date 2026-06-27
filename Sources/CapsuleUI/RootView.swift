//
//  RootView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import SwiftUI

/// The top-level UI.
///
/// It binds only to the domain's `WorkspaceModel`; it must never import a backend
/// module (enforced by `ArchitectureGuardTests` and `Scripts/check-architecture.sh`).
public struct RootView: View {
    @State private var model: WorkspaceModel

    public init(model: WorkspaceModel) {
        self._model = State(initialValue: model)
    }

    public var body: some View {
        NavigationSplitView {
            List(ResourceKind.allCases) { kind in
                Label(kind.rawValue.capitalized, systemImage: kind.symbolName)
            }
            .navigationTitle("Capsule")
        } detail: {
            ResourcePlaceholder(state: model.loadState)
        }
        .task { await model.refresh() }
    }
}

extension ResourceKind {
    /// SF Symbol used to represent the resource kind in the sidebar.
    var symbolName: String {
        switch self {
        case .container: return "shippingbox"
        case .image: return "square.stack.3d.up"
        case .volume: return "externaldrive"
        case .network: return "network"
        }
    }
}
