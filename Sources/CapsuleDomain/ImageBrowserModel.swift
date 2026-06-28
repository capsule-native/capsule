//
//  ImageBrowserModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The images read
//  surface, mirroring `ContainerBrowserModel`: a loaded list with a live query (search +
//  sort + a dangling filter), a multi-selection, and raw-retaining inspect. Image actions
//  (tag/delete/prune) live in `ImageActionsModel`; transfers live in `TaskCenter`.

import CapsuleBackend
import Foundation
import Observation

/// The load state of the image list, kept separate from `rows` so the UI can distinguish
/// "service unreachable" from "no images" from "no matches".
public enum ImageLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case unavailable(ErrorDetail)
}

/// How the image list is ordered.
public enum ImageSort: String, Sendable, CaseIterable, Identifiable {
    case name
    case size
    case created

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .name: return "Name"
        case .size: return "Size"
        case .created: return "Created"
        }
    }
}

/// An image inspection: the decoded domain value (nil if the payload drifted) paired with
/// the exact raw JSON, so the inspector can always show *something*.
public struct ImageInspection: Sendable, Equatable {
    public var value: Image?
    public var rawJSON: String

    public init(value: Image?, rawJSON: String) {
        self.value = value
        self.rawJSON = rawJSON
    }
}

@MainActor
@Observable
public final class ImageBrowserModel {
    public private(set) var allImages: [Image] = []
    public private(set) var loadState: ImageLoadState = .idle

    public var searchText: String = ""
    public var sort: ImageSort = .name
    public var showDanglingOnly: Bool = false
    public var selection: Set<Image.ID> = []

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.backend = backend
        self.normalize = normalize
        self.onActivity = onActivity
    }

    // MARK: Derived views

    /// Images passing the dangling filter and search term, ordered by the active sort.
    public var rows: [Image] {
        allImages
            .filter { !showDanglingOnly || $0.isDangling }
            .filter { matchesSearch($0) }
            .sorted(by: ordering)
    }

    public var selectedImages: [Image] {
        allImages.filter { selection.contains($0.id) }
    }

    /// The service is up but there are genuinely no images (distinct from a down service
    /// and from a filter that matched nothing).
    public var isEmptyButHealthy: Bool {
        loadState == .loaded && allImages.isEmpty
    }

    /// There are images, but the active filter/search matched none.
    public var noMatches: Bool {
        loadState == .loaded && !allImages.isEmpty && rows.isEmpty
    }

    private func matchesSearch(_ image: Image) -> Bool {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        return image.reference.localizedCaseInsensitiveContains(term)
            || image.repository.localizedCaseInsensitiveContains(term)
            || (image.tag?.localizedCaseInsensitiveContains(term) ?? false)
            || image.digest.localizedCaseInsensitiveContains(term)
    }

    /// Name sorts ascending; size sorts largest-first; created sorts newest-first with
    /// undated images last. Ties break on the reference for a stable order.
    private func ordering(_ lhs: Image, _ rhs: Image) -> Bool {
        switch sort {
        case .name:
            return lhs.reference.localizedCaseInsensitiveCompare(rhs.reference) == .orderedAscending
        case .size:
            if lhs.sizeBytes != rhs.sizeBytes { return lhs.sizeBytes > rhs.sizeBytes }
            return lhs.reference.localizedCaseInsensitiveCompare(rhs.reference) == .orderedAscending
        case .created:
            switch (lhs.createdAt, rhs.createdAt) {
            case let (l?, r?) where l != r: return l > r
            case (nil, .some): return false
            case (.some, nil): return true
            default:
                return lhs.reference.localizedCaseInsensitiveCompare(rhs.reference)
                    == .orderedAscending
            }
        }
    }

    // MARK: Loading

    public func refresh() async {
        loadState = .loading
        do {
            let summaries = try await backend.listImages()
            allImages = summaries.map(Image.init(summary:))
            selection = selection.intersection(Set(allImages.map(\.id)))
            loadState = .loaded
            onActivity("Loaded \(allImages.count) image(s).")
        } catch {
            allImages = []
            let detail = normalize(error).detail
            onActivity("Failed to load images: \(detail.title)")
            loadState = .unavailable(detail)
        }
    }

    /// Inspects one image, mapping the backend's raw-retaining `Parsed` into the domain
    /// `ImageInspection`. Never throws: a failure yields an empty raw payload.
    public func inspect(reference: String) async -> ImageInspection {
        do {
            let parsed = try await backend.inspectImage(reference: reference)
            return ImageInspection(
                value: parsed.value.map(Image.init(summary:)),
                rawJSON: parsed.raw
            )
        } catch {
            return ImageInspection(value: nil, rawJSON: "")
        }
    }
}
