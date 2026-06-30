//
//  StorageDashboardModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`.

import CapsuleBackend
import Foundation
import Observation

public enum StorageCategory: String, Sendable, CaseIterable, Identifiable {
    case images, containers, volumes
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .images: return "Images"
        case .containers: return "Containers"
        case .volumes: return "Volumes"
        }
    }
}

public struct CleanupRecommendation: Sendable, Equatable, Identifiable {
    public var category: StorageCategory
    public var reclaimableBytes: Int
    public var id: String { category.rawValue }
}

public enum StorageLoadState: Sendable, Equatable {
    case idle, loading, loaded, unavailable(ErrorDetail)
}

@MainActor
@Observable
public final class StorageDashboardModel {
    public private(set) var usage: StorageUsage?
    public private(set) var loadState: StorageLoadState = .idle

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onReclaim: @MainActor (StorageCategory) -> Void

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onReclaim: @escaping @MainActor (StorageCategory) -> Void = { _ in }
    ) {
        self.backend = backend
        self.normalize = normalize
        self.onReclaim = onReclaim
    }

    public func refresh() async {
        loadState = .loading
        do {
            let u = try await backend.systemDiskUsage()
            usage = u
            loadState = .loaded
        } catch {
            loadState = .unavailable(normalize(error).detail)
        }
    }

    private func category(_ c: StorageCategory) -> CategoryUsage? {
        switch c {
        case .images: return usage?.images
        case .containers: return usage?.containers
        case .volumes: return usage?.volumes
        }
    }

    public var recommendations: [CleanupRecommendation] {
        StorageCategory.allCases.compactMap { c in
            guard let u = category(c), u.reclaimable > 0 else { return nil }
            return CleanupRecommendation(category: c, reclaimableBytes: u.reclaimable)
        }
    }

    public var totalReclaimableBytes: Int {
        StorageCategory.allCases.reduce(0) { $0 + (category($1)?.reclaimable ?? 0) }
    }
    public var totalInUseBytes: Int {
        StorageCategory.allCases.reduce(0) { $0 + (category($1)?.inUseBytes ?? 0) }
    }

    public func reclaim(_ category: StorageCategory) { onReclaim(category) }
}
