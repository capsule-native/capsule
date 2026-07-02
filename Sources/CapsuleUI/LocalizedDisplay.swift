//
//  LocalizedDisplay.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Localized display accessors for the Domain display enums the UI renders. The Domain
//  intentionally exposes only plain `String` labels (it must stay UI- and locale-free); the
//  raw `String` properties feed logs, ids, and tests. These accessors live in `CapsuleUI`
//  so their default text is extracted into this module's String Catalog and resolved against
//  `Bundle.module` at render time — letting views switch `Text(x.title)` (verbatim, never
//  localized) to `Text(x.localizedTitle)` (localized) without the Domain ever importing UI.
//
//  Keep each default value BYTE-FOR-BYTE identical to the Domain's English label: the
//  extractor keys on that exact string, and drift would silently create a second catalog key.

import CapsuleDomain
import SwiftUI

/// Resolves a `LocalizedStringResource` against `CapsuleUI`'s `Bundle.module` so the value is
/// both extracted into this module's String Catalog and looked up there at runtime.
private func uiString(_ value: String.LocalizationValue) -> LocalizedStringResource {
    LocalizedStringResource(value, bundle: .atURL(Bundle.module.bundleURL))
}

// MARK: - ContainerStateFilter

extension ContainerStateFilter {
    /// The filter's label, localized. Mirrors ``ContainerStateFilter/title`` exactly.
    public var localizedTitle: LocalizedStringResource {
        switch self {
        case .all: return uiString("All")
        case .running: return uiString("Running")
        case .stopped: return uiString("Stopped")
        case .created: return uiString("Created")
        }
    }
}

// MARK: - ContainerState

extension ContainerState {
    /// A localized, human-readable label for the container's lifecycle state. The Domain enum
    /// has no `title`; this is the UI's presentation of each case.
    public var localizedTitle: LocalizedStringResource {
        switch self {
        case .created: return uiString("Created")
        case .running: return uiString("Running")
        case .paused: return uiString("Paused")
        case .stopping: return uiString("Stopping")
        case .stopped: return uiString("Stopped")
        case .unknown: return uiString("Unknown")
        }
    }
}

// MARK: - ImageSort

extension ImageSort {
    /// The sort's label, localized. Mirrors ``ImageSort/title`` exactly.
    public var localizedTitle: LocalizedStringResource {
        switch self {
        case .name: return uiString("Name")
        case .size: return uiString("Size")
        case .created: return uiString("Created")
        }
    }
}

// MARK: - SystemHealth

extension SystemHealth {
    /// The one-word status label, localized. Mirrors ``SystemHealth/statusLabel`` exactly.
    public var localizedStatusLabel: LocalizedStringResource {
        switch self {
        case .unknown, .checking: return uiString("Checking…")
        case .running: return uiString("Running")
        case .stopped: return uiString("Stopped")
        case .unavailable: return uiString("Unavailable")
        case .notInstalled: return uiString("Not Installed")
        }
    }
}

// MARK: - OperationKind

extension OperationKind {
    /// The operation's title, localized. Mirrors ``OperationKind/title`` exactly.
    public var localizedTitle: LocalizedStringResource {
        switch self {
        case .pull: return uiString("Pull")
        case .push: return uiString("Push")
        case .save: return uiString("Save")
        case .load: return uiString("Load")
        case .build: return uiString("Build")
        case .run: return uiString("Run")
        case .export: return uiString("Export")
        case .systemStart: return uiString("Start Services")
        case .copy: return uiString("Copy")
        case .machineCreate: return uiString("Create Machine")
        case .systemKernelInstall: return uiString("Install Kernel")
        }
    }
}

// MARK: - RecoveryAction

extension RecoveryAction {
    /// The action button's title, localized. Mirrors ``RecoveryAction/title`` exactly,
    /// including the interpolated permission name for `grantPermission`.
    public var localizedTitle: LocalizedStringResource {
        switch self {
        case .retry: return uiString("Try Again")
        case .retryInTerminal: return uiString("Retry in Terminal")
        case .startServices: return uiString("Start Services")
        case .installContainerCLI: return uiString("Install container…")
        case .openLogs: return uiString("Open Logs")
        case .editConfiguration: return uiString("Edit Configuration")
        case .exportDiagnostics: return uiString("Export Diagnostics")
        case let .grantPermission(kind): return uiString("Grant \(kind.title)")
        }
    }
}

// MARK: - PermissionKind

extension PermissionKind {
    /// The permission's label, localized. Mirrors ``PermissionKind/title`` exactly.
    public var localizedTitle: LocalizedStringResource {
        switch self {
        case .administrator: return uiString("Administrator access")
        case .fileAccess: return uiString("File access")
        case .network: return uiString("Network access")
        }
    }
}

// MARK: - StorageCategory

extension StorageCategory {
    /// The category's label, localized. Mirrors ``StorageCategory/title`` exactly.
    public var localizedTitle: LocalizedStringResource {
        switch self {
        case .images: return uiString("Images")
        case .containers: return uiString("Containers")
        case .volumes: return uiString("Volumes")
        }
    }
}

// MARK: - CopyDirection

extension CopyDirection {
    /// The direction's label, localized. Mirrors ``CopyDirection/title`` exactly.
    public var localizedTitle: LocalizedStringResource {
        switch self {
        case .toContainer: return uiString("Host → Container")
        case .fromContainer: return uiString("Container → Host")
        }
    }
}

// Note: `MachineImagePreset.displayName` values are proper distro identifiers
// ("Ubuntu 24.04", "Alpine 3.22") — product-version proper nouns, not translatable prose.
// They are rendered with `Text(verbatim:)` at the call site rather than routed through the
// catalog (a single `%@` catalog key would give translators nothing to translate).

// MARK: - Accessibility

/// A tiny reusable announcer for streaming/transcript panes, so a view can push a spoken
/// VoiceOver update (e.g. "Pull finished") without importing the AppKit accessibility API at
/// each call site. Posting is a safe no-op when VoiceOver is off.
public enum CapsuleAccessibility {
    /// Posts a VoiceOver announcement for `message`, resolved against this module's bundle.
    @MainActor
    public static func announce(_ message: LocalizedStringResource) {
        // `Announcement` takes a resolved string; resolving the resource localizes it against
        // its carried bundle before it's spoken.
        AccessibilityNotification.Announcement(String(localized: message)).post()
    }
}
