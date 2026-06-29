//
//  MachineListView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleDomain
import SwiftUI

struct MachineListView: View {
    @Bindable var model: MachineBrowserModel
    let actions: MachineActionsModel
    var body: some View {
        Text("Machines").task { await model.refresh() }
    }
}
