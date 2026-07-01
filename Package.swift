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
//     CapsuleApp        ──▶ CapsuleUI, CapsuleTerminal, CapsuleCLIBackend, CapsuleRegistryClient,
//                           CapsuleAutomation, CapsuleDiagnostics, CapsuleDomain, CapsuleBackend
//     CapsuleTerminal   ──▶ CapsuleUI, CapsuleDomain, SwiftTerm  (engine adapter)
//     CapsuleUI         ──▶ CapsuleDomain
//     CapsuleAutomation ──▶ CapsuleBackend                      (leaf / side; drives the port)
//     CapsuleDiagnostics──▶ CapsuleDomain, CapsuleBackend       (leaf / side)
//     CapsuleCLIBackend ──▶ CapsuleBackend, CapsuleDiagnostics  (adapter; conforms to port)
//     CapsuleRegistryClient ──▶ CapsuleBackend                  (adapter; conforms to the search port)
//     CapsuleDomain     ──▶ CapsuleBackend                      (the port)
//     CapsuleBackend    ──▶ (no Capsule dependencies)           (port; bottom of the graph)
//
// Hard rules (enforced by `Tests/CapsuleUnitTests/ArchitectureGuardTests` and
// `Scripts/check-architecture.sh`): UI never imports a Backend module (port or
// adapter), and Domain never imports UI (nor uses Foundation.Process). The domain maps
// backend value types into its own models so backend types never reach the UI.
let package = Package(
    name: "Capsule",
    // Required the moment any target ships a localized resource (String Catalog). Every
    // user-facing string resolves against its module's catalog with this as the base.
    defaultLocalization: "en",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "CapsuleApp", targets: ["CapsuleApp"]),
        .library(name: "CapsuleUI", targets: ["CapsuleUI"]),
        .library(name: "CapsuleDomain", targets: ["CapsuleDomain"]),
        .library(name: "CapsuleBackend", targets: ["CapsuleBackend"]),
        .library(name: "CapsuleCLIBackend", targets: ["CapsuleCLIBackend"]),
        .library(name: "CapsuleRegistryClient", targets: ["CapsuleRegistryClient"]),
        .library(name: "CapsuleAutomation", targets: ["CapsuleAutomation"]),
        .library(name: "CapsuleDiagnostics", targets: ["CapsuleDiagnostics"]),
        .library(name: "CapsuleTerminal", targets: ["CapsuleTerminal"]),
    ],
    dependencies: [
        // First external dependency: a mature, MIT, pure-Swift terminal emulator. `from:`
        // floors the major; the exact resolved version is pinned in Package.resolved
        // (committed). `swift package resolve` (Step 4) picks the latest 1.x.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0"),
        // Auto-updates for the UNSANDBOXED, Developer-ID-signed distribution (Milestone 13).
        // Sparkle ships via SwiftPM as a signed binary xcframework; only the composition root
        // (CapsuleApp) links it, behind the `UpdaterController` seam so the rest of the app —
        // and every unit test — stays free of any Sparkle dependency.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
    ],
    targets: [
        // MARK: - Port layer (bottom of the graph; no Capsule dependencies)
        .target(name: "CapsuleBackend"),

        // MARK: - Domain (depends on the backend port only; no UI, no Process)
        // Owns the app's user-facing *display* strings (state labels, sort/filter titles,
        // error explanations) as localized resources — hence its own String Catalog.
        .target(
            name: "CapsuleDomain",
            dependencies: ["CapsuleBackend"],
            resources: [.process("Resources")]
        ),

        // MARK: - Leaf / side modules
        .target(name: "CapsuleDiagnostics", dependencies: ["CapsuleDomain", "CapsuleBackend"]),
        // Automation (App Intents + AppleScript vocabulary) drives the backend *port* directly
        // for headless invocation — hence the CapsuleBackend dependency (the port + value
        // types, no Process). It is a side/leaf the app composes; the architecture guard only
        // restricts UI and Domain, so importing the port here is allowed.
        .target(
            name: "CapsuleAutomation",
            dependencies: ["CapsuleBackend"],
            resources: [.process("Resources")]
        ),

        // MARK: - CLI adapter (conforms to the backend port; the only Process user)
        .target(
            name: "CapsuleCLIBackend",
            dependencies: ["CapsuleBackend", "CapsuleDiagnostics"]
        ),

        // MARK: - Registry-search adapter (URLSession; the only first-party HTTP user)
        // Conforms to the `ImageRegistrySearching` port with an unauthenticated Docker Hub
        // client. Depends only on the port, so further registries can be adapted beside it
        // and neither UI nor Domain ever see the HTTP layer.
        .target(
            name: "CapsuleRegistryClient",
            dependencies: ["CapsuleBackend"]
        ),

        // MARK: - Presentation (Domain only — must NOT import any Backend module)
        // Ships the UI String Catalog; library-authored user-facing strings resolve against
        // this target's `Bundle.module`.
        .target(
            name: "CapsuleUI",
            dependencies: ["CapsuleDomain"],
            resources: [.process("Resources")]
        ),

        // MARK: - Terminal engine adapter (SwiftTerm/PTY; conforms to the UI port).
        // May import CapsuleUI + CapsuleDomain only; wired by the composition root.
        .target(
            name: "CapsuleTerminal",
            dependencies: [
                "CapsuleUI",
                "CapsuleDomain",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            // One user-facing string (the terminal's VoiceOver label) resolves against this
            // target's own catalog.
            resources: [.process("Resources")]
        ),

        // MARK: - Composition root / app lifecycle (wires the adapter into the domain)
        // The ONLY target that links Sparkle: it supplies the `SparkleUpdaterController` that
        // backs CapsuleUI's `UpdaterController` seam. Keeping the import here means `swift test`
        // and every library target build without Sparkle in their graph.
        .target(
            name: "CapsuleApp",
            dependencies: [
                "CapsuleUI",
                "CapsuleTerminal",
                "CapsuleDomain",
                "CapsuleBackend",
                "CapsuleCLIBackend",
                "CapsuleRegistryClient",
                "CapsuleAutomation",
                "CapsuleDiagnostics",
                .product(name: "Sparkle", package: "Sparkle"),
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
                "CapsuleRegistryClient",
                "CapsuleAutomation",
                "CapsuleDiagnostics",
            ],
            // Real `container --format json` captures, used to verify decoding without
            // spawning the CLI. See Tests/CapsuleUnitTests/Fixtures.
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CapsuleIntegrationTests",
            dependencies: ["CapsuleApp", "CapsuleCLIBackend", "CapsuleBackend", "CapsuleDomain"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
