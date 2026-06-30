//
//  StorageDashboardView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Storage dashboard: per-category GroupBox cards (images / containers / volumes) with
//  size, in-use, and reclaimable totals, plus a "Reclaim N" action button per card and
//  a grand-total reclaimable row at the bottom.

import CapsuleDomain
import SwiftUI

struct StorageDashboardView: View {
    @Bindable var model: StorageDashboardModel

    var body: some View {
        Group {
            switch model.loadState {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable(let detail):
                ContentUnavailableView(
                    detail.title,
                    systemImage: "internaldrive",
                    description: Text(detail.explanation)
                )
            case .loaded:
                ScrollView { content }
            }
        }
        .task { await model.refresh() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(StorageCategory.allCases) { category in
                categoryCard(for: category)
            }
            LabeledContent("Total reclaimable") {
                Text(Int64(model.totalReclaimableBytes), format: .byteCount(style: .file))
                    .monospacedDigit()
            }
            .font(.headline)
        }
        .padding()
    }

    @ViewBuilder
    private func categoryCard(for category: StorageCategory) -> some View {
        switch category {
        case .images:
            if let u = model.usage?.images {
                StorageCategoryCard(
                    category: category,
                    sizeInBytes: u.sizeInBytes,
                    inUseBytes: u.inUseBytes,
                    reclaimable: u.reclaimable
                ) { model.reclaim(category) }
            }
        case .containers:
            if let u = model.usage?.containers {
                StorageCategoryCard(
                    category: category,
                    sizeInBytes: u.sizeInBytes,
                    inUseBytes: u.inUseBytes,
                    reclaimable: u.reclaimable
                ) { model.reclaim(category) }
            }
        case .volumes:
            if let u = model.usage?.volumes {
                StorageCategoryCard(
                    category: category,
                    sizeInBytes: u.sizeInBytes,
                    inUseBytes: u.inUseBytes,
                    reclaimable: u.reclaimable
                ) { model.reclaim(category) }
            }
        }
    }
}

private struct StorageCategoryCard: View {
    let category: StorageCategory
    let sizeInBytes: Int
    let inUseBytes: Int
    let reclaimable: Int
    let onReclaim: () -> Void

    var body: some View {
        GroupBox(category.title) {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Total") {
                    Text(Int64(sizeInBytes), format: .byteCount(style: .file))
                }
                LabeledContent("In use") {
                    Text(Int64(inUseBytes), format: .byteCount(style: .file))
                }
                LabeledContent("Reclaimable") {
                    Text(Int64(reclaimable), format: .byteCount(style: .file))
                }
                if reclaimable > 0 {
                    let label =
                        "Reclaim \(Int64(reclaimable).formatted(.byteCount(style: .file)))…"
                    Button(label, action: onReclaim)
                }
            }
            .padding(6)
        }
    }
}
