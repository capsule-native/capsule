//
//  Image.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The domain's
//  model of a container image — decoupled from the backend wire format, with the reference
//  parsed into repository/tag and the digest surfaced for unambiguous copy actions.

import CapsuleBackend
import Foundation

/// The domain's model of a container image.
public struct Image: Sendable, Equatable, Identifiable {
    public var reference: String
    public var repository: String
    public var tag: String?
    /// The full content digest (`sha256:…`), used verbatim for digest-centric copy actions.
    public var digest: String
    /// The backend's own image identifier (the CLI's `id`), accepted by `inspect`/`delete`/
    /// `tag`. Used to address dangling images, whose `<none>:<none>` reference is not usable.
    public var imageID: String
    public var sizeBytes: Int64
    public var createdAt: Date?

    public init(
        reference: String, repository: String, tag: String?, digest: String,
        imageID: String, sizeBytes: Int64, createdAt: Date? = nil
    ) {
        self.reference = reference
        self.repository = repository
        self.tag = tag
        self.digest = digest
        self.imageID = imageID
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
    }

    /// A row id that doubles as the CLI identifier: the reference for tagged images, and the
    /// backend id for dangling images (whose `<none>:<none>` reference can't address them).
    public var id: String { isDangling ? imageID : reference }

    /// An untagged / unreferenced image (`<none>`), the prune target.
    public var isDangling: Bool { reference.isEmpty || reference.contains("<none>") }

    /// The leading 12 hex characters of the digest (after any `sha256:` prefix), for
    /// compact display alongside the full, copyable digest.
    public var shortDigest: String {
        let hex = digest.hasPrefix("sha256:") ? String(digest.dropFirst(7)) : digest
        return String(hex.prefix(12))
    }

    /// A user-facing name: the reference, or "<none>" for a dangling image.
    public var displayName: String { isDangling ? "<none>" : reference }
}

extension Image {
    /// Maps a backend summary into the domain model, parsing the reference and date.
    public init(summary: ImageSummary) {
        let (repository, tag) = Image.parse(reference: summary.reference)
        self.init(
            reference: summary.reference,
            repository: repository,
            tag: tag,
            digest: summary.digest,
            imageID: summary.id,
            sizeBytes: summary.sizeBytes,
            createdAt: summary.createdAt.flatMap(Container.parseDate)
        )
    }

    /// Splits an image reference into `(repository, tag?)`.
    ///
    /// A digest-pinned reference (`name@sha256:…`) has no tag. A tag is only the text after
    /// the last `:` *within the final path segment*, so a registry port (`localhost:5000/…`)
    /// is never mistaken for a tag.
    static func parse(reference: String) -> (repository: String, tag: String?) {
        // Digest-pinned: everything before `@` is the repository, no tag.
        if let at = reference.firstIndex(of: "@") {
            return (String(reference[..<at]), nil)
        }
        let lastSlash = reference.lastIndex(of: "/")
        let segmentStart = lastSlash.map { reference.index(after: $0) } ?? reference.startIndex
        guard let colon = reference[segmentStart...].lastIndex(of: ":") else {
            return (reference, nil)
        }
        let tag = String(reference[reference.index(after: colon)...])
        // A dangling image reports `<none>:<none>` — that placeholder is not a real tag.
        return (String(reference[..<colon]), tag == "<none>" ? nil : tag)
    }
}
