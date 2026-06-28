// swift-tools-version: 6.0
//
//  Package.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import PackageDescription

// Capsule's reusable core lives here as a set of strictly-layered modules.
// The macOS app bundle (Info.plist, entitlements, hardened runtime, asset catalog,
// UI tests) is provided by a thin Xcode app target generated from `App/project.yml`
// (`make xcodeproj`) that consumes these library products.
//
// Dependency direction (X -> Y means "X depends on Y"):
//
//     CapsuleApp        ──▶ CapsuleUI, CapsuleCLIBackend, CapsuleAutomation,
//                           CapsuleDiagnostics, CapsuleDomain, CapsuleBackend
//     CapsuleUI         ──▶ CapsuleDomain
//     CapsuleAutomation ──▶ CapsuleDomain                       (leaf / side)
//     CapsuleDiagnostics──▶ CapsuleDomain                       (leaf / side)
//     CapsuleCLIBackend ──▶ CapsuleBackend, CapsuleDiagnostics  (adapter; conforms to port)
//     CapsuleDomain     ──▶ CapsuleBackend                      (the port)
//     CapsuleBackend    ──▶ (no Capsule dependencies)           (port; bottom of the graph)
//
// Hard rules (enforced by `Tests/CapsuleUnitTests/ArchitectureGuardTests` and
// `Scripts/check-architecture.sh`): UI never imports a Backend module (port or
// adapter), and Domain never imports UI (nor uses Foundation.Process). The domain maps
// backend value types into its own models so backend types never reach the UI.
let package = Package(
    name: "Capsule",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "CapsuleApp", targets: ["CapsuleApp"]),
        .library(name: "CapsuleUI", targets: ["CapsuleUI"]),
        .library(name: "CapsuleDomain", targets: ["CapsuleDomain"]),
        .library(name: "CapsuleBackend", targets: ["CapsuleBackend"]),
        .library(name: "CapsuleCLIBackend", targets: ["CapsuleCLIBackend"]),
        .library(name: "CapsuleAutomation", targets: ["CapsuleAutomation"]),
        .library(name: "CapsuleDiagnostics", targets: ["CapsuleDiagnostics"]),
    ],
    targets: [
        // MARK: - Port layer (bottom of the graph; no Capsule dependencies)
        .target(name: "CapsuleBackend"),

        // MARK: - Domain (depends on the backend port only; no UI, no Process)
        .target(name: "CapsuleDomain", dependencies: ["CapsuleBackend"]),

        // MARK: - Leaf / side modules
        .target(name: "CapsuleDiagnostics", dependencies: ["CapsuleDomain"]),
        .target(name: "CapsuleAutomation", dependencies: ["CapsuleDomain"]),

        // MARK: - CLI adapter (conforms to the backend port; the only Process user)
        .target(
            name: "CapsuleCLIBackend",
            dependencies: ["CapsuleBackend", "CapsuleDiagnostics"]
        ),

        // MARK: - Presentation (Domain only — must NOT import any Backend module)
        .target(name: "CapsuleUI", dependencies: ["CapsuleDomain"]),

        // MARK: - Composition root / app lifecycle (wires the adapter into the domain)
        .target(
            name: "CapsuleApp",
            dependencies: [
                "CapsuleUI",
                "CapsuleDomain",
                "CapsuleBackend",
                "CapsuleCLIBackend",
                "CapsuleAutomation",
                "CapsuleDiagnostics",
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "CapsuleUnitTests",
            dependencies: [
                "CapsuleApp",
                "CapsuleUI",
                "CapsuleDomain",
                "CapsuleBackend",
                "CapsuleCLIBackend",
                "CapsuleAutomation",
                "CapsuleDiagnostics",
            ],
            // Real `container --format json` captures, used to verify decoding without
            // spawning the CLI. See Tests/CapsuleUnitTests/Fixtures.
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CapsuleIntegrationTests",
            dependencies: ["CapsuleCLIBackend", "CapsuleBackend", "CapsuleDomain"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
