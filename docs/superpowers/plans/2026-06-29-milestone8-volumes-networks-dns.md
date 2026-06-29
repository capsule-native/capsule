# Milestone 8 · Volumes, Networks & DNS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the storage and networking surfaces (Volumes & Networks browsers with create/inspect/delete/prune) plus local DNS under Settings, making Capsule a credible full wrapper.

**Architecture:** Ports & Adapters, reusing the M5–M7 stacks verbatim — the resource browser/inspector stack, the draft-model + `validatedConfiguration()` + command-preview sheet stack, the pure `ConfirmationRequest`/`ConfirmationKind` + generic `ConfirmationSheet`, the prune-preview sheet, the `LifecycleNotice` → `ErrorDetail` → `RecoveryActionButtons` error path, the M2 capability flags, and the M7 `openCommandInTerminalApp` handoff. No new architectural concepts.

**Tech Stack:** Swift (SwiftPM strict-layered modules + thin XcodeGen app target), SwiftUI + Observation, XCTest, the `container` CLI v1.0.0 runtime.

Design spec: `docs/superpowers/specs/2026-06-29-milestone8-volumes-networks-dns-design.md`.
Phases are implemented **in order** (1 → 6); each task ends with an independently testable deliverable.

## Global Constraints

Every task's requirements implicitly include this section.

### Environment, layering & build
- **Platform:** Apple silicon, macOS 26+, unsandboxed, Hardened Runtime, notarized. Runtime is the `container` CLI v1.0.0.
- **Layering (arch-guard: `make arch` + `ArchitectureGuardTests`):** `CapsuleUI` imports **no** `CapsuleBackend`/`CapsuleCLIBackend`; `CapsuleDomain` imports **no** `CapsuleUI` and **no** `Foundation.Process`; `CapsuleDomain` **may** import `CapsuleBackend` (protocol + value types + Configurations). `CapsuleApp` is the only composition root.
- **argv single-source-of-truth:** all argv is built by `*Configuration.arguments` (in `CapsuleBackend`) or `CLICommand` static builders (in `CapsuleCLIBackend`) — never hand-concatenated in models or views. Secrets never go on argv.
- **Build/test:** `make build` (= `swift build`); `make test` (= `swift test`, with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` exported — required for XCTest); focused: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter <TestCaseClass>`; static checks: `make check` (lint+arch+headers); full gate: `make ci`.
- **Every new Swift file** starts with the project license header (Appendix A §3). Pre-commit hooks run swift-format + the header check — run `make format` before committing if needed. Commit messages end with the two required trailer lines (`Co-Authored-By:` + `Claude-Session:`).
- **TDD throughout:** failing test → verify it fails → minimal implementation → verify it passes → commit. Frequent, small commits. DRY, YAGNI.

### Domain rules (from the spec's binding decisions)
- **No force-delete:** the CLI has no `--force` for `volume`/`network` delete; an in-use resource simply errors. Confirmation kinds carry no `force`. **Builtin networks** (label `com.apple.container.resource.role: builtin`, e.g. `default`) are protected: Delete disabled, `ConfirmationRequest.deleteNetwork` returns `nil`, excluded from prune/bulk.
- **Create/delete/prune are synchronous** (busy set + `LifecycleNotice` on failure), **not** Activity tasks — no new `OperationKind`. **Prune previews are best-effort** (computed via `AttachmentIndex`; the CLI owns the authoritative set; actual reclaimed shown after).
- **DNS create/delete** never run in-process: they build `DNSConfiguration` argv and route through a **direct `sudo` Terminal handoff**. `system dns list` is unprivileged. `ErrorNormalizer` maps `(try sudo?)` / "must run as an administrator" → `permissionRequired(.administrator)` (safety net); the `.grantPermission(.administrator)` recovery handler carries no command, so it surfaces guidance pointing to Settings › Networking (where Add/Delete perform the privileged handoff).

### Plan-wide execution rules (binding — these resolve cross-phase conflicts found in adversarial review)
- **Phase ownership (no cross-phase duplication):**
  - **Phase 1** owns the volume/network/dns **backend** only (Configurations, `CLICommand` builders, `VolumeSummary`/`NetworkSummary`/`DNSDomainSummary`, volume/network/dns wire models + parsers, the nine `ContainerBackend` methods on `MockBackend` + `CLIContainerBackend`, `MockBackend` mutation recorders, and the **`ErrorNormalizer` administrator-signature mapping**). Phase 1 does **not** touch the container wire model/parser.
  - **Phase 2** owns **container attachment data** (`CLIContainerRecord` mounts/networks, `OutputParser.parseContainers`, `ContainerSummary`/`Container` `volumeMounts`/`networkNames`, `ContainerAttachmentInfo`, `AttachmentIndex`, `CIDR`) and captures the real `containers-with-mounts.json` fixture.
  - **`ErrorNormalization.swift`** is edited **only** by Phase 1 Task 1.6; Phases 5 consume the result.
  - **Capability gating** is owned **only** by Phase 6; Phases 3/4 add only their routing + inspector arms.
- **Create/Add sheets** (`CreateVolumeSheet`/`CreateNetworkSheet`/`AddDNSDomainSheet`, in `CapsuleUI`) must **not** name any `*Configuration` type or call `.arguments`. They consume only Domain primitives: a command-preview `String` from the model and a validity accessor (`canCreate`/`validationMessage`), submitting via a draft-taking model method (`create(draft:)`/`add()`). Mirror M7 `QuickRunSheet`/`BuildSheet`.
- **Additive shared-file edits:** `AppEnvironment.swift`, `ContentColumnView.swift`, `AppShellView.swift`, `PreferencesView.swift`, `CapsuleScene.swift`, and `Confirmation.swift` are edited by multiple phases and applied **sequentially in phase order**. Every edit is **additive** — insert the new switch arm / enum case / static builder / inspector case / notice overlay assuming earlier phases' additions are present; never replace a whole switch/enum/struct body.
- **Notice rendering:** every `*ActionsModel` that sets `notice` on failure gets a matching `LifecycleNoticeView` overlay in `AppShellView` (dismiss → `model.notice = nil`).

---

## Phase 1: Backend foundations (volumes, networks, DNS)

This phase delivers the entire `CapsuleBackend` / `CapsuleCLIBackend` foundation for volumes, networks, and DNS: the three `*Configuration` argv single-sources, the new `CLICommand` builders, the enriched `VolumeSummary` / `NetworkSummary` / new `DNSDomainSummary` value types, the **volume/network/dns** wire models + parsers, the nine new `ContainerBackend` methods implemented on **both** `MockBackend` and `CLIContainerBackend` (with `MockBackend` mutation recorders for assertions), the `ErrorNormalizer` administrator-signature mapping, and the real + hand-built Phase-1 fixtures (`volume-ls`, `volume-inspect`, `network-inspect`, `dns-ls`).

**Ownership boundary (binding):** Phase 1 does **NOT** touch the CONTAINER wire model/parser or `ContainerSummary`. There are no `parseContainers` changes, no `CLIContainerRecord.configuration.mounts/networks` decoding, no `ContainerSummary.volumeMounts/networkNames`, and no container-with-mounts fixture here — that attachment data is Phase 2's responsibility. Phase 1 fixtures are `volume-ls`, `volume-inspect`, `network-inspect`, `dns-ls` only.

It is the first phase, so it consumes nothing from earlier phases. Later phases consume from it by exact name: `VolumeConfiguration`/`NetworkConfiguration`/`DNSConfiguration`, the enriched value types and their new fields, `OutputParser.parseVolumes`/`parseNetworks`/`parseDNS`, the nine protocol methods, the `MockBackend` recorders, and `CapsuleError.permissionRequired(kind: .administrator, …)`.

All work is on the already-created branch `milestone-8-volumes-networks-dns`. Every new file starts with the license header from §3 of the contract. Run `make format` before each commit (pre-commit hooks run swift-format + the license-header check).

---

### Task 1.1: Capture Phase-1 fixtures (volume-ls, volume-inspect, network-inspect) + hand-build dns-ls + README provenance

These data files are the prerequisite for the decode tests in Task 1.4. The `volume-ls`/`volume-inspect`/`network-inspect` files are **real captures** obtained by creating a throwaway volume + network against the live `container` v1.0.0 CLI; `dns-ls` is **hand-built schema-faithfully** (the DNS list is sudo-gated and empty on the dev machine). They are auto-bundled by the test target's existing `resources: [.copy("Fixtures")]` (Package.swift needs no change). No container-with-mounts fixture is captured here — that belongs to Phase 2.

**Files:**
- Create: `Tests/CapsuleUnitTests/Fixtures/volume-ls.json`
- Create: `Tests/CapsuleUnitTests/Fixtures/volume-inspect.json`
- Create: `Tests/CapsuleUnitTests/Fixtures/network-inspect.json`
- Create: `Tests/CapsuleUnitTests/Fixtures/dns-ls.json`
- Modify: `Tests/CapsuleUnitTests/Fixtures/README.md` (append four provenance rows)

**Interfaces:**
- Consumes: nothing.
- Produces: bundled fixtures loadable via `Fixture.data("volume-ls")`, `Fixture.data("volume-inspect")`, `Fixture.data("network-inspect")`, `Fixture.data("dns-ls")` (the existing `Fixture` enum in `Fixtures.swift`).

**Steps:**

- [ ] **Step 1: Confirm the branch and clean tree.** Run `git status` and `git branch --show-current`; expect branch `milestone-8-volumes-networks-dns` and a clean tree. If not on the branch: `git checkout milestone-8-volumes-networks-dns`.

- [ ] **Step 2: (Provenance record) capture the real volume/network JSON against the live CLI.** This is exactly how the three real fixtures below were produced (resources created then deleted; the dev machine is left at baseline — empty volumes, only the `default` network):
  ```bash
  container volume create --label role=scratch -s 512M capsule-m8-probe
  container volume list --format json          # -> volume-ls.json content
  container volume inspect capsule-m8-probe     # -> volume-inspect.json content
  container network create --label tier=test --subnet 10.88.0.0/24 capsule-m8-net
  container network inspect capsule-m8-net      # -> network-inspect.json content
  container volume delete capsule-m8-probe
  container network delete capsule-m8-net
  ```

- [ ] **Step 3: Write `Tests/CapsuleUnitTests/Fixtures/volume-ls.json`** (real capture, `container volume list --format json` with one throwaway volume):
  ```json
  [{"configuration":{"creationDate":"2026-06-29T07:15:32Z","driver":"local","format":"ext4","labels":{"role":"scratch"},"name":"capsule-m8-probe","options":{"size":"512M"},"sizeInBytes":536870912,"source":"/Users/baroman/Library/Application Support/com.apple.container/volumes/capsule-m8-probe/volume.img"},"id":"capsule-m8-probe"}]
  ```

- [ ] **Step 4: Write `Tests/CapsuleUnitTests/Fixtures/volume-inspect.json`** (real capture, `container volume inspect <name>` — pretty JSON array, no `--format` flag):
  ```json
  [
    {
      "configuration" : {
        "creationDate" : "2026-06-29T07:15:32Z",
        "driver" : "local",
        "format" : "ext4",
        "labels" : {
          "role" : "scratch"
        },
        "name" : "capsule-m8-probe",
        "options" : {
          "size" : "512M"
        },
        "sizeInBytes" : 536870912,
        "source" : "/Users/baroman/Library/Application Support/com.apple.container/volumes/capsule-m8-probe/volume.img"
      },
      "id" : "capsule-m8-probe"
    }
  ]
  ```

- [ ] **Step 5: Write `Tests/CapsuleUnitTests/Fixtures/network-inspect.json`** (real capture, `container network inspect <name>` for a **non-builtin** created network — its `configuration.labels` does NOT carry the `com.apple.container.resource.role: builtin` marker):
  ```json
  [
    {
      "configuration" : {
        "creationDate" : "2026-06-29T07:15:32Z",
        "ipv4Subnet" : "10.88.0.0/24",
        "labels" : {
          "tier" : "test"
        },
        "mode" : "nat",
        "name" : "capsule-m8-net",
        "options" : {

        },
        "plugin" : "container-network-vmnet"
      },
      "id" : "capsule-m8-net",
      "status" : {
        "ipv4Gateway" : "10.88.0.1",
        "ipv4Subnet" : "10.88.0.0/24",
        "ipv6Subnet" : "fd65:1ffc:2bce:b6aa::/64"
      }
    }
  ]
  ```

- [ ] **Step 6: Write `Tests/CapsuleUnitTests/Fixtures/dns-ls.json`** (hand-built, schema-faithful). The DNS list is sudo-gated and empty on the dev machine, so a real populated capture is impossible. The keys (`domainName`, `localhost`) are pinned from the apple/container v1.0.0 binary's `CodingKeys` (`strings` over `/usr/local/bin/container` shows `_domainName`/`domainName` and `localhost`; the `-q`/table form prints only the domain, the help string is "the local domain name"):
  ```json
  [{"domainName":"capsule.test","localhost":"127.0.0.1"}]
  ```

- [ ] **Step 7: Append four provenance rows to `Tests/CapsuleUnitTests/Fixtures/README.md`** (under the existing table):
  ```markdown
  | `volume-ls.json` | **Real capture** — `container volume list --format json` (CLI v1.0.0) after `container volume create --label role=scratch -s 512M capsule-m8-probe`. Nested `{configuration{…}, id}` shape; `sizeInBytes`, `driver`, `format`, `options`, `labels`, `creationDate`. Throwaway volume deleted afterward. |
  | `volume-inspect.json` | **Real capture** — `container volume inspect capsule-m8-probe` (pretty JSON array; `volume inspect` has no `--format` flag). Same record as `volume-ls.json`. |
  | `network-inspect.json` | **Real capture** — `container network inspect capsule-m8-net` for a **non-builtin** network created with `--label tier=test --subnet 10.88.0.0/24` (so `isBuiltin == false`). Carries `configuration.{plugin,labels,creationDate}` and `status.{ipv4Gateway,ipv4Subnet,ipv6Subnet}`. Throwaway network deleted afterward. |
  | `dns-ls.json` | **Schema-faithful, hand-built.** `system dns list` is administrator-gated and empty on the dev machine, so it cannot be captured populated. Keys (`domainName`, `localhost`) pinned from the apple/container **1.0.0** binary's `CodingKeys` (`_domainName`/`domainName`, `localhost`) and the `system dns create --localhost <ip> <domain-name>` help surface. |
  ```

- [ ] **Step 8: Sanity-check the JSON is well-formed** (no test target rebuild needed):
  ```bash
  for f in volume-ls volume-inspect network-inspect dns-ls; do \
    python3 -m json.tool "Tests/CapsuleUnitTests/Fixtures/$f.json" > /dev/null && echo "$f OK"; done
  ```
  Expect: `volume-ls OK`, `volume-inspect OK`, `network-inspect OK`, `dns-ls OK`.

- [ ] **Step 9: Commit.**
  ```bash
  git add Tests/CapsuleUnitTests/Fixtures/volume-ls.json \
          Tests/CapsuleUnitTests/Fixtures/volume-inspect.json \
          Tests/CapsuleUnitTests/Fixtures/network-inspect.json \
          Tests/CapsuleUnitTests/Fixtures/dns-ls.json \
          Tests/CapsuleUnitTests/Fixtures/README.md
  git commit -m "test(m8): capture volume/network fixtures + hand-build dns-ls

Real captures (volume-ls, volume-inspect, network-inspect) from container
v1.0.0 by creating + deleting a throwaway volume and network; dns-ls is
hand-built schema-faithfully (sudo-gated, empty on this machine). Provenance
documented in Fixtures/README.md. Container attachment fixtures are Phase 2.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
  ```

---

### Task 1.2: Configurations — VolumeConfiguration, NetworkConfiguration, DNSConfiguration

The argv single-source-of-truth value types, in `CapsuleBackend` beside `RunConfiguration`/`BuildConfiguration`. Each is `Sendable, Equatable` with a computed `arguments: [String]` (flags first, positional last). `DNSConfiguration` additionally exposes `deleteArguments`; its `arguments`/`deleteArguments` are the privileged-handoff argv (never run through the CLI adapter).

**Files:**
- Create: `Sources/CapsuleBackend/VolumeConfiguration.swift`
- Create: `Sources/CapsuleBackend/NetworkConfiguration.swift`
- Create: `Sources/CapsuleBackend/DNSConfiguration.swift`
- Create: `Tests/CapsuleUnitTests/VolumeConfigurationTests.swift`
- Create: `Tests/CapsuleUnitTests/NetworkConfigurationTests.swift`
- Create: `Tests/CapsuleUnitTests/DNSConfigurationTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `VolumeConfiguration(name: String, size: String? = nil, options: [String] = [], labels: [String] = [])` with `var arguments: [String]`.
  - `NetworkConfiguration(name: String, subnet: String? = nil, subnetV6: String? = nil, internal: Bool = false, options: [String] = [], labels: [String] = [], plugin: String? = nil)` with `var arguments: [String]`.
  - `DNSConfiguration(domain: String, localhostIP: String? = nil)` with `var arguments: [String]` and `var deleteArguments: [String]`.

**Steps:**

- [ ] **Step 1: Write the failing tests.** Create `Tests/CapsuleUnitTests/VolumeConfigurationTests.swift`:
  ```swift
  //
  //  VolumeConfigurationTests.swift
  //  Capsule
  //
  //  Copyright © 2026 Capsule. All rights reserved.
  //
  //  VolumeConfiguration.arguments is the single source of truth for the
  //  `container volume create` argv: labels, then opts, then size, then the name.

  import CapsuleBackend
  import XCTest

  final class VolumeConfigurationTests: XCTestCase {
      func testMinimalArgv() {
          XCTAssertEqual(VolumeConfiguration(name: "data").arguments, ["volume", "create", "data"])
      }

      func testSizeOnlyUsesShortFlag() {
          XCTAssertEqual(
              VolumeConfiguration(name: "data", size: "512M").arguments,
              ["volume", "create", "-s", "512M", "data"])
      }

      func testFullArgvOrdersLabelsThenOptsThenSizeThenName() {
          let config = VolumeConfiguration(
              name: "data", size: "10G",
              options: ["type=ext4", "journal=ordered"],
              labels: ["env=dev", "team=infra"])
          XCTAssertEqual(
              config.arguments,
              [
                  "volume", "create",
                  "--label", "env=dev", "--label", "team=infra",
                  "--opt", "type=ext4", "--opt", "journal=ordered",
                  "-s", "10G", "data",
              ])
      }

      func testEquatable() {
          XCTAssertEqual(
              VolumeConfiguration(name: "data", size: "1G"),
              VolumeConfiguration(name: "data", size: "1G"))
      }
  }
  ```
  Create `Tests/CapsuleUnitTests/NetworkConfigurationTests.swift`:
  ```swift
  //
  //  NetworkConfigurationTests.swift
  //  Capsule
  //
  //  Copyright © 2026 Capsule. All rights reserved.
  //
  //  NetworkConfiguration.arguments is the single source of truth for the
  //  `container network create` argv: --internal, labels, options, plugin,
  //  subnet, subnet-v6, then the name.

  import CapsuleBackend
  import XCTest

  final class NetworkConfigurationTests: XCTestCase {
      func testMinimalArgv() {
          XCTAssertEqual(
              NetworkConfiguration(name: "app-net").arguments, ["network", "create", "app-net"])
      }

      func testSubnetOnly() {
          XCTAssertEqual(
              NetworkConfiguration(name: "app-net", subnet: "10.0.0.0/24").arguments,
              ["network", "create", "--subnet", "10.0.0.0/24", "app-net"])
      }

      func testInternalOnly() {
          XCTAssertEqual(
              NetworkConfiguration(name: "app-net", internal: true).arguments,
              ["network", "create", "--internal", "app-net"])
      }

      func testFullArgvOrdering() {
          let config = NetworkConfiguration(
              name: "app-net", subnet: "10.0.0.0/24", subnetV6: "fd00::/64",
              internal: true, options: ["mtu=1500"], labels: ["env=dev"],
              plugin: "container-network-vmnet")
          XCTAssertEqual(
              config.arguments,
              [
                  "network", "create", "--internal",
                  "--label", "env=dev",
                  "--option", "mtu=1500",
                  "--plugin", "container-network-vmnet",
                  "--subnet", "10.0.0.0/24",
                  "--subnet-v6", "fd00::/64",
                  "app-net",
              ])
      }
  }
  ```
  Create `Tests/CapsuleUnitTests/DNSConfigurationTests.swift`:
  ```swift
  //
  //  DNSConfigurationTests.swift
  //  Capsule
  //
  //  Copyright © 2026 Capsule. All rights reserved.
  //
  //  DNSConfiguration is the argv source for the privileged sudo Terminal handoff
  //  (system dns create/delete). It is never run through the CLI adapter.

  import CapsuleBackend
  import XCTest

  final class DNSConfigurationTests: XCTestCase {
      func testCreateArgvMinimal() {
          XCTAssertEqual(
              DNSConfiguration(domain: "capsule.test").arguments,
              ["system", "dns", "create", "capsule.test"])
      }

      func testCreateArgvWithLocalhost() {
          XCTAssertEqual(
              DNSConfiguration(domain: "capsule.test", localhostIP: "127.0.0.1").arguments,
              ["system", "dns", "create", "--localhost", "127.0.0.1", "capsule.test"])
      }

      func testDeleteArgv() {
          XCTAssertEqual(
              DNSConfiguration(domain: "capsule.test").deleteArguments,
              ["system", "dns", "delete", "capsule.test"])
      }
  }
  ```

- [ ] **Step 2: Run the tests; expect a build failure.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter VolumeConfigurationTests`
  Expected FAIL: compile error `cannot find 'VolumeConfiguration' in scope` (and likewise `NetworkConfiguration`, `DNSConfiguration`).

- [ ] **Step 3: Write `Sources/CapsuleBackend/VolumeConfiguration.swift`:**
  ```swift
  //
  //  VolumeConfiguration.swift
  //  Capsule
  //
  //  Copyright © 2026 Capsule. All rights reserved.
  //
  //  A typed description of a `container volume create` invocation. Its `arguments` is the
  //  single source of truth for the argv (after the `container` executable), shared by the
  //  CLI adapter and the domain's create sheet. Flags mirror `container volume create`
  //  v1.0.0 (verified against `--help`): no --driver / --source / --name flags exist;
  //  `-s <size>` accepts a K/M/G/T/P suffix.

  import Foundation

  public struct VolumeConfiguration: Sendable, Equatable {
      public var name: String
      /// Size string rendered as `-s <value>` (pre-validated K/M/G/T/P suffix).
      public var size: String?
      /// Driver options as `k=v` tokens, each emitted as `--opt k=v`.
      public var options: [String]
      /// Labels as `k=v` tokens, each emitted as `--label k=v`.
      public var labels: [String]

      public init(
          name: String,
          size: String? = nil,
          options: [String] = [],
          labels: [String] = []
      ) {
          self.name = name
          self.size = size
          self.options = options
          self.labels = labels
      }

      /// The argv after `container`: labels, then opts, then size, then the positional name.
      public var arguments: [String] {
          var argv = ["volume", "create"]
          for label in labels { argv += ["--label", label] }
          for opt in options { argv += ["--opt", opt] }
          if let size { argv += ["-s", size] }
          argv.append(name)
          return argv
      }
  }
  ```

- [ ] **Step 4: Write `Sources/CapsuleBackend/NetworkConfiguration.swift`:**
  ```swift
  //
  //  NetworkConfiguration.swift
  //  Capsule
  //
  //  Copyright © 2026 Capsule. All rights reserved.
  //
  //  A typed description of a `container network create` invocation. Its `arguments` is the
  //  single source of truth for the argv (after the `container` executable), shared by the
  //  CLI adapter and the domain's create sheet. Flags mirror `container network create`
  //  v1.0.0 (verified against `--help`): the gateway is derived from the subnet (not set
  //  directly); the default plugin is `container-network-vmnet`.

  import Foundation

  public struct NetworkConfiguration: Sendable, Equatable {
      public var name: String
      public var subnet: String?
      public var subnetV6: String?
      public var `internal`: Bool
      /// Driver options as `k=v` tokens, each emitted as `--option k=v`.
      public var options: [String]
      /// Labels as `k=v` tokens, each emitted as `--label k=v`.
      public var labels: [String]
      public var plugin: String?

      public init(
          name: String,
          subnet: String? = nil,
          subnetV6: String? = nil,
          internal: Bool = false,
          options: [String] = [],
          labels: [String] = [],
          plugin: String? = nil
      ) {
          self.name = name
          self.subnet = subnet
          self.subnetV6 = subnetV6
          self.internal = `internal`
          self.options = options
          self.labels = labels
          self.plugin = plugin
      }

      /// The argv after `container`: --internal, labels, options, plugin, subnet,
      /// subnet-v6, then the positional name.
      public var arguments: [String] {
          var argv = ["network", "create"]
          if `internal` { argv.append("--internal") }
          for label in labels { argv += ["--label", label] }
          for opt in options { argv += ["--option", opt] }
          if let plugin { argv += ["--plugin", plugin] }
          if let subnet { argv += ["--subnet", subnet] }
          if let subnetV6 { argv += ["--subnet-v6", subnetV6] }
          argv.append(name)
          return argv
      }
  }
  ```

- [ ] **Step 5: Write `Sources/CapsuleBackend/DNSConfiguration.swift`:**
  ```swift
  //
  //  DNSConfiguration.swift
  //  Capsule
  //
  //  Copyright © 2026 Capsule. All rights reserved.
  //
  //  A typed description of the privileged `container system dns create/delete` invocations.
  //  `system dns create`/`delete` MUST run as an administrator, so this argv is consumed by
  //  the domain DNS model and executed via the App-layer sudo Terminal handoff — it is
  //  NEVER run through the CLI adapter. Flags mirror `container system dns` v1.0.0.

  import Foundation

  public struct DNSConfiguration: Sendable, Equatable {
      public var domain: String
      public var localhostIP: String?

      public init(domain: String, localhostIP: String? = nil) {
          self.domain = domain
          self.localhostIP = localhostIP
      }

      /// Privileged create argv — consumed by the DNS model + the sudo Terminal handoff.
      public var arguments: [String] {
          var argv = ["system", "dns", "create"]
          if let localhostIP { argv += ["--localhost", localhostIP] }
          argv.append(domain)
          return argv
      }

      /// Privileged delete argv companion.
      public var deleteArguments: [String] { ["system", "dns", "delete", domain] }
  }
  ```

- [ ] **Step 6: Run the tests; expect PASS.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter VolumeConfigurationTests`
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NetworkConfigurationTests`
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DNSConfigurationTests`
  Expected: all pass (`Executed N tests, with 0 failures`).

- [ ] **Step 7: Commit.**
  ```bash
  make format
  git add Sources/CapsuleBackend/VolumeConfiguration.swift \
          Sources/CapsuleBackend/NetworkConfiguration.swift \
          Sources/CapsuleBackend/DNSConfiguration.swift \
          Tests/CapsuleUnitTests/VolumeConfigurationTests.swift \
          Tests/CapsuleUnitTests/NetworkConfigurationTests.swift \
          Tests/CapsuleUnitTests/DNSConfigurationTests.swift
  git commit -m "feat(m8): VolumeConfiguration/NetworkConfiguration/DNSConfiguration argv

argv single-source-of-truth types beside RunConfiguration: volume create
(labels/opts/size/name), network create (internal/labels/options/plugin/
subnet/subnet-v6/name), and the privileged dns create/delete argv.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
  ```

---

### Task 1.3: CLICommand builders for volumes, networks, DNS list

Add the typed argv factories. `createVolume`/`createNetwork` delegate to the configuration's `arguments` (mirroring `CLICommand.run`/`build`); the rest assemble via `ArgumentBuilder`. DNS create/delete are intentionally **not** here (Domain cannot import `CapsuleCLIBackend`).

**Files:**
- Modify: `Sources/CapsuleCLIBackend/CLICommand.swift` (extend the "Volumes / networks / registries / machines / builder" MARK section, after `builderStatus()` at line ~195)
- Modify: `Tests/CapsuleUnitTests/CLICommandTests.swift` (add three test methods)

**Interfaces:**
- Consumes: `VolumeConfiguration.arguments`, `NetworkConfiguration.arguments` (Task 1.2); `ArgumentBuilder` (existing).
- Produces: `CLICommand.inspectVolume(names:)`, `.createVolume(_:)`, `.deleteVolumes(names:)`, `.pruneVolumes()`, `.inspectNetwork(names:)`, `.createNetwork(_:)`, `.deleteNetworks(names:)`, `.pruneNetworks()`, `.listDNSDomains()` — each `-> [String]`.

**Steps:**

- [ ] **Step 1: Write the failing tests** — add to `Tests/CapsuleUnitTests/CLICommandTests.swift`:
  ```swift
  func testVolumeCommands() {
      XCTAssertEqual(
          CLICommand.inspectVolume(names: ["a", "b"]), ["volume", "inspect", "a", "b"])
      let createConfig = VolumeConfiguration(name: "data", size: "1G")
      XCTAssertEqual(CLICommand.createVolume(createConfig), createConfig.arguments)
      XCTAssertEqual(
          CLICommand.createVolume(createConfig), ["volume", "create", "-s", "1G", "data"])
      XCTAssertEqual(CLICommand.deleteVolumes(names: ["a", "b"]), ["volume", "delete", "a", "b"])
      XCTAssertEqual(CLICommand.pruneVolumes(), ["volume", "prune"])
  }

  func testNetworkCommands() {
      XCTAssertEqual(CLICommand.inspectNetwork(names: ["n1"]), ["network", "inspect", "n1"])
      let createConfig = NetworkConfiguration(name: "app-net", subnet: "10.0.0.0/24")
      XCTAssertEqual(CLICommand.createNetwork(createConfig), createConfig.arguments)
      XCTAssertEqual(
          CLICommand.deleteNetworks(names: ["n1", "n2"]), ["network", "delete", "n1", "n2"])
      XCTAssertEqual(CLICommand.pruneNetworks(), ["network", "prune"])
  }

  func testDNSListCommand() {
      XCTAssertEqual(CLICommand.listDNSDomains(), ["system", "dns", "list", "--format", "json"])
  }
  ```

- [ ] **Step 2: Run; expect FAIL.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CLICommandTests/testVolumeCommands`
  Expected FAIL: compile error `type 'CLICommand' has no member 'inspectVolume'`.

- [ ] **Step 3: Implement** — append to the "Volumes / networks / registries / machines / builder" section of `Sources/CapsuleCLIBackend/CLICommand.swift` (after `builderStatus()`):
  ```swift
      // MARK: - Volume mutation / inspection

      public static func inspectVolume(names: [String]) -> [String] {
          // `container volume inspect` does not accept `--format`; it emits JSON by default.
          ArgumentBuilder("volume", "inspect").adding(contentsOf: names).arguments
      }

      public static func createVolume(_ config: VolumeConfiguration) -> [String] {
          config.arguments
      }

      public static func deleteVolumes(names: [String]) -> [String] {
          ArgumentBuilder("volume", "delete").adding(contentsOf: names).arguments
      }

      public static func pruneVolumes() -> [String] {
          ArgumentBuilder("volume", "prune").arguments
      }

      // MARK: - Network mutation / inspection

      public static func inspectNetwork(names: [String]) -> [String] {
          // `container network inspect` does not accept `--format`; it emits JSON by default.
          ArgumentBuilder("network", "inspect").adding(contentsOf: names).arguments
      }

      public static func createNetwork(_ config: NetworkConfiguration) -> [String] {
          config.arguments
      }

      public static func deleteNetworks(names: [String]) -> [String] {
          ArgumentBuilder("network", "delete").adding(contentsOf: names).arguments
      }

      public static func pruneNetworks() -> [String] {
          ArgumentBuilder("network", "prune").arguments
      }

      // MARK: - DNS (list only; create/delete are privileged via DNSConfiguration)

      public static func listDNSDomains() -> [String] {
          ArgumentBuilder("system", "dns", "list").flag("--format", "json").arguments
      }
  ```

- [ ] **Step 4: Run; expect PASS.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CLICommandTests`
  Expected: pass (all existing + the three new methods).

- [ ] **Step 5: Commit.**
  ```bash
  make format
  git add Sources/CapsuleCLIBackend/CLICommand.swift Tests/CapsuleUnitTests/CLICommandTests.swift
  git commit -m "feat(m8): CLICommand builders for volume/network mutation + dns list

inspect/create/delete/prune for volumes and networks (create delegates to the
typed config; inspect carries no --format), plus the unprivileged dns list argv.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
  ```

---

### Task 1.4: Value-type extensions + volume/network/dns wire models + parsers

Extend `VolumeSummary`/`NetworkSummary`, add `DNSDomainSummary` (all new fields defaulted so call sites keep compiling); enrich the **volume/network** wire models to the real nested shapes pinned by the Task-1.1 fixtures and add `CLIDNSRecord`; and extend `OutputParser` with `parseVolumes`/`parseNetworks`/`parseDNS`. The failing tests are the decode assertions against the real fixtures.

> **Ownership (binding):** this task does **NOT** touch `CLIContainerRecord`, `OutputParser.parseContainers`, or `ContainerSummary`. The container attachment data (`configuration.mounts[].source` / `configuration.networks[].network`, `ContainerSummary.volumeMounts`/`networkNames`) and its `containers-with-mounts` parse test are owned by Phase 2. Phase 1's wire/parser work is limited to volumes, networks, and DNS.

> **Schema reconciliation (binding):** the live `container volume list --format json` nests fields under `configuration` (with `sizeInBytes`, `driver`, `format`, `creationDate`) and a top-level `id` — not the flat shape contract Appendix A §4.4 sketched. `CLIVolumeRecord` is internal to `CapsuleCLIBackend` (no cross-phase dependency), so it is pinned to the **real** nested shape while retaining flat `name`/`source` fallbacks, keeping the existing `OutputParserTests.testParsesPopulatedVolumeAndMachineAndRegistry` (flat input) green. The cross-phase contract — `VolumeSummary` and `OutputParser.parseVolumes` — is unchanged. The DNS primary key is `domainName` (pinned from the binary), with `domain`/`name` fallbacks per the contract's "accept either key."

**Files:**
- Modify: `Sources/CapsuleBackend/BackendResourceTypes.swift` (extend `VolumeSummary` lines 43–53, `NetworkSummary` lines 55–76; add `DNSDomainSummary`)
- Modify: `Sources/CapsuleCLIBackend/WireModels.swift` (extend `CLINetworkRecord` lines 119–133, `CLIVolumeRecord` lines 142–145; add `CLIDNSRecord`)
- Modify: `Sources/CapsuleCLIBackend/OutputParser.swift` (extend `parseNetworks` lines 136–146, `parseVolumes` lines 150–155; add `parseDNS`)
- Modify: `Tests/CapsuleUnitTests/OutputParserTests.swift` (add decode tests)

**Interfaces:**
- Consumes: fixtures `volume-ls`, `volume-inspect`, `network-ls` (existing), `network-inspect`, `dns-ls` (Task 1.1).
- Produces:
  - `VolumeSummary(name:source:sizeBytes:options:labels:createdAt:)` with `sizeBytes: Int64?`, `options: [String:String]`, `labels: [String:String]`, `createdAt: String?`.
  - `NetworkSummary(id:name:mode:gateway:subnet:plugin:ipv6Subnet:labels:createdAt:isBuiltin:)`.
  - `DNSDomainSummary(domain:localhostIP:)`, `id == domain`.
  - `OutputParser.parseVolumes(_:) -> [VolumeSummary]`, `parseNetworks(_:) -> [NetworkSummary]`, `parseDNS(_:) -> [DNSDomainSummary]`.

**Steps:**

- [ ] **Step 1: Write the failing tests** — add to `Tests/CapsuleUnitTests/OutputParserTests.swift`. Replace the existing `// MARK: - Networks` section's single test with an enriched set, and append volume + DNS tests:
  ```swift
      // MARK: - Networks (M8 enrichment)

      func testParsesRealNetworkListIntoRowsWithBuiltinMarker() throws {
          let rows = try OutputParser.parseNetworks(Fixture.data("network-ls"))

          let network = try XCTUnwrap(rows.first)
          XCTAssertEqual(network.id, "default")
          XCTAssertEqual(network.name, "default")
          XCTAssertEqual(network.mode, "nat")
          XCTAssertEqual(network.gateway, "192.168.64.1")
          XCTAssertEqual(network.subnet, "192.168.64.0/24")
          XCTAssertEqual(network.plugin, "container-network-vmnet")
          XCTAssertEqual(network.ipv6Subnet, "fdb6:5eb:8ee:85cf::/64")
          XCTAssertTrue(network.isBuiltin, "the resource.role:builtin label marks it protected")
          XCTAssertEqual(network.labels["com.apple.container.resource.role"], "builtin")
      }

      func testParsesNetworkInspectAsNonBuiltin() throws {
          let rows = try OutputParser.parseNetworks(Fixture.data("network-inspect"))

          let network = try XCTUnwrap(rows.first)
          XCTAssertEqual(network.name, "capsule-m8-net")
          XCTAssertEqual(network.subnet, "10.88.0.0/24")
          XCTAssertEqual(network.gateway, "10.88.0.1")
          XCTAssertEqual(network.ipv6Subnet, "fd65:1ffc:2bce:b6aa::/64")
          XCTAssertFalse(network.isBuiltin, "a user-created network is not builtin")
          XCTAssertEqual(network.labels["tier"], "test")
      }

      // MARK: - Volumes (M8 enrichment)

      func testParsesRealVolumeListWithMetadata() throws {
          let rows = try OutputParser.parseVolumes(Fixture.data("volume-ls"))

          XCTAssertEqual(rows.count, 1)
          let volume = try XCTUnwrap(rows.first)
          XCTAssertEqual(volume.name, "capsule-m8-probe")
          XCTAssertEqual(volume.sizeBytes, 536_870_912)
          XCTAssertEqual(volume.options["size"], "512M")
          XCTAssertEqual(volume.labels["role"], "scratch")
          XCTAssertEqual(volume.createdAt, "2026-06-29T07:15:32Z")
          XCTAssertEqual(volume.source?.hasSuffix("capsule-m8-probe/volume.img"), true)
      }

      func testParsesVolumeInspectPayload() throws {
          let rows = try OutputParser.parseVolumes(Fixture.data("volume-inspect"))
          XCTAssertEqual(rows.first?.name, "capsule-m8-probe")
          XCTAssertEqual(rows.first?.sizeBytes, 536_870_912)
      }

      // MARK: - DNS (M8)

      func testParsesDNSDomains() throws {
          let rows = try OutputParser.parseDNS(Fixture.data("dns-ls"))
          XCTAssertEqual(rows.count, 1)
          XCTAssertEqual(rows.first?.domain, "capsule.test")
          XCTAssertEqual(rows.first?.localhostIP, "127.0.0.1")
          XCTAssertEqual(rows.first?.id, "capsule.test")
      }

      func testParsesEmptyDNSList() throws {
          XCTAssertEqual(try OutputParser.parseDNS(Data("[]".utf8)).count, 0)
      }

      func testParseDNSAcceptsDomainAndNameFallbackKeys() throws {
          let byDomain = try OutputParser.parseDNS(Data(#"[{"domain":"a.test"}]"#.utf8))
          XCTAssertEqual(byDomain.first?.domain, "a.test")
          let byName = try OutputParser.parseDNS(Data(#"[{"name":"b.test"}]"#.utf8))
          XCTAssertEqual(byName.first?.domain, "b.test")
      }
  ```
  Delete the old `testParsesRealNetworkListIntoRows` (it is superseded by `…WithBuiltinMarker`). Keep `testParsesPopulatedVolumeAndMachineAndRegistry` (it exercises the flat fallback) and `testParsesRealEmptyCapturesAsEmptyLists`. Do **not** add any container-attachment test here — that is Phase 2.

- [ ] **Step 2: Run; expect FAIL.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OutputParserTests`
  Expected FAIL: compile errors — `value of type 'NetworkSummary' has no member 'plugin'`, `… 'isBuiltin'`, `… 'VolumeSummary' has no member 'sizeBytes'`, `type 'OutputParser' has no member 'parseDNS'`.

- [ ] **Step 3: Extend the value types** — replace `VolumeSummary` and `NetworkSummary` in `Sources/CapsuleBackend/BackendResourceTypes.swift` and add `DNSDomainSummary` after `RegistrySummary`:
  ```swift
  /// A backend's lightweight view of a volume.
  public struct VolumeSummary: Sendable, Equatable, Identifiable, Codable {
      public var id: String { name }
      public var name: String
      public var source: String?
      public var sizeBytes: Int64?
      public var options: [String: String]
      public var labels: [String: String]
      /// Raw ISO-8601 creation timestamp; the domain parses it into a `Date`.
      public var createdAt: String?

      public init(
          name: String,
          source: String? = nil,
          sizeBytes: Int64? = nil,
          options: [String: String] = [:],
          labels: [String: String] = [:],
          createdAt: String? = nil
      ) {
          self.name = name
          self.source = source
          self.sizeBytes = sizeBytes
          self.options = options
          self.labels = labels
          self.createdAt = createdAt
      }
  }

  /// A backend's lightweight view of a network.
  public struct NetworkSummary: Sendable, Equatable, Identifiable, Codable {
      public var id: String
      public var name: String
      public var mode: String?
      public var gateway: String?
      public var subnet: String?
      public var plugin: String?
      public var ipv6Subnet: String?
      public var labels: [String: String]
      /// Raw ISO-8601 creation timestamp; the domain parses it into a `Date`.
      public var createdAt: String?
      /// True for runtime-managed networks (labeled `…resource.role: builtin`, e.g. `default`)
      /// that must not be deleted.
      public var isBuiltin: Bool

      public init(
          id: String,
          name: String,
          mode: String? = nil,
          gateway: String? = nil,
          subnet: String? = nil,
          plugin: String? = nil,
          ipv6Subnet: String? = nil,
          labels: [String: String] = [:],
          createdAt: String? = nil,
          isBuiltin: Bool = false
      ) {
          self.id = id
          self.name = name
          self.mode = mode
          self.gateway = gateway
          self.subnet = subnet
          self.plugin = plugin
          self.ipv6Subnet = ipv6Subnet
          self.labels = labels
          self.createdAt = createdAt
          self.isBuiltin = isBuiltin
      }
  }

  /// A backend's lightweight view of a local DNS domain (`system dns list`).
  public struct DNSDomainSummary: Sendable, Equatable, Identifiable, Codable {
      public var id: String { domain }
      public var domain: String
      public var localhostIP: String?

      public init(domain: String, localhostIP: String? = nil) {
          self.domain = domain
          self.localhostIP = localhostIP
      }
  }
  ```

- [ ] **Step 4: Enrich the volume/network/dns wire models** — in `Sources/CapsuleCLIBackend/WireModels.swift`, replace `CLINetworkRecord` and `CLIVolumeRecord`, and add `CLIDNSRecord`. **Do not** add `mounts`/`networks` to `CLIContainerRecord.Configuration` — that is Phase 2.
  - Replace `CLINetworkRecord`:
  ```swift
  struct CLINetworkRecord: Decodable {
      let id: String
      let configuration: Configuration
      let status: Status?

      struct Configuration: Decodable {
          let name: String
          let mode: String?
          let plugin: String?
          let labels: [String: String]?
          let options: [String: String]?
          let creationDate: String?
      }

      struct Status: Decodable {
          let ipv4Gateway: String?
          let ipv4Subnet: String?
          let ipv6Subnet: String?
      }

      /// Runtime-managed networks (e.g. `default`) carry this label and must not be deleted.
      var isBuiltin: Bool {
          configuration.labels?["com.apple.container.resource.role"] == "builtin"
      }
  }
  ```
  - Replace `CLIVolumeRecord` (real nested shape pinned by `volume-ls`/`volume-inspect`, with flat fallbacks):
  ```swift
  // Real-capture shape: `container volume list/inspect` nests fields under `configuration`
  // (sizeInBytes/driver/format/options/labels/creationDate) with a top-level `id`. This
  // nested shape supersedes the flat sketch in contract Appendix A §4.4; the flat name/source
  // fields remain only as lenient fallbacks for an alternate/older shape.
  struct CLIVolumeRecord: Decodable {
      let id: String?
      let configuration: Configuration?
      // Flat fallbacks for an alternate/older shape (keeps lenient decode tolerant).
      let name: String?
      let source: String?

      struct Configuration: Decodable {
          let name: String?
          let source: String?
          let driver: String?
          let format: String?
          let labels: [String: String]?
          let options: [String: String]?
          let sizeInBytes: Int64?
          let creationDate: String?
      }

      var resolvedName: String? { configuration?.name ?? name ?? id }
      var resolvedSource: String? { configuration?.source ?? source }
      var resolvedSizeBytes: Int64? { configuration?.sizeInBytes }
      var resolvedOptions: [String: String] { configuration?.options ?? [:] }
      var resolvedLabels: [String: String] { configuration?.labels ?? [:] }
      var resolvedCreatedAt: String? { configuration?.creationDate }
  }
  ```
  - Add `CLIDNSRecord` (in the volumes/registries/machines MARK section):
  ```swift
  /// One element of `container system dns list --format json`. The list is sudo-gated and
  /// empty on the dev machine, so the keys are pinned schema-faithfully from the apple/
  /// container 1.0.0 binary. Real-capture key: the primary key is `domainName` (with
  /// `localhost`), which supersedes the `domain`/`name`-only sketch in contract Appendix A
  /// §4.4 — those remain accepted as fallbacks. Lenient + all-optional, like the other
  /// empty-observed families.
  struct CLIDNSRecord: Decodable {
      let domainName: String?
      let domain: String?
      let name: String?
      let localhost: String?

      var resolvedDomain: String? { domainName ?? domain ?? name }
  }
  ```

- [ ] **Step 5: Extend the parsers** in `Sources/CapsuleCLIBackend/OutputParser.swift`. **Do not** modify `parseContainers` — that is Phase 2.
  - Replace `parseNetworks`:
  ```swift
      public static func parseNetworks(_ data: Data) throws -> [NetworkSummary] {
          try lossyList(data, decode: CLINetworkRecord.self).map { record in
              NetworkSummary(
                  id: record.id,
                  name: record.configuration.name,
                  mode: record.configuration.mode,
                  gateway: record.status?.ipv4Gateway,
                  subnet: record.status?.ipv4Subnet,
                  plugin: record.configuration.plugin,
                  ipv6Subnet: record.status?.ipv6Subnet,
                  labels: record.configuration.labels ?? [:],
                  createdAt: record.configuration.creationDate,
                  isBuiltin: record.isBuiltin
              )
          }
      }
  ```
  - Replace `parseVolumes`:
  ```swift
      public static func parseVolumes(_ data: Data) throws -> [VolumeSummary] {
          try lossyList(data, decode: CLIVolumeRecord.self).compactMap { record in
              guard let name = record.resolvedName else { return nil }
              return VolumeSummary(
                  name: name,
                  source: record.resolvedSource,
                  sizeBytes: record.resolvedSizeBytes,
                  options: record.resolvedOptions,
                  labels: record.resolvedLabels,
                  createdAt: record.resolvedCreatedAt
              )
          }
      }
  ```
  - Add `parseDNS` (in the volumes/registries/machines section):
  ```swift
      public static func parseDNS(_ data: Data) throws -> [DNSDomainSummary] {
          try lossyList(data, decode: CLIDNSRecord.self).compactMap { record in
              guard let domain = record.resolvedDomain else { return nil }
              return DNSDomainSummary(domain: domain, localhostIP: record.localhost)
          }
      }
  ```

- [ ] **Step 6: Run; expect PASS.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OutputParserTests`
  Then the full suite to confirm no existing call site broke (defaulted fields):
  `make test`
  Expected: all pass.

- [ ] **Step 7: Commit.**
  ```bash
  make format
  git add Sources/CapsuleBackend/BackendResourceTypes.swift \
          Sources/CapsuleCLIBackend/WireModels.swift \
          Sources/CapsuleCLIBackend/OutputParser.swift \
          Tests/CapsuleUnitTests/OutputParserTests.swift
  git commit -m "feat(m8): enrich volume/network value types, wire models, parsers

VolumeSummary gains sizeBytes/options/labels/createdAt; NetworkSummary gains
plugin/ipv6Subnet/labels/createdAt/isBuiltin; add DNSDomainSummary (all
defaulted). Wire models pinned to the real nested volume shape + DNS domainName
key (supersedes Appendix A); parseVolumes/parseNetworks/parseDNS proven against
the Phase-1 fixtures. Container attachment data is Phase 2.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
  ```

---

### Task 1.5: ContainerBackend protocol additions + MockBackend (with recorders) + CLIContainerBackend

Add the nine new methods to the protocol and implement them on **both** adapters in one task — adding a protocol requirement breaks compilation of every conformer until all conform, so the failing tests here are the new `MockBackendTests`/`CLIContainerBackendTests` that won't compile until the protocol + both adapters land together. Prune methods return `PruneResult` (contract decision §4.1). `MockBackend` gains mutation **recorders** (spec §4.5 "record last create/delete/prune argv for assertions") that the new `MockBackendTests` assert against.

**Files:**
- Modify: `Sources/CapsuleBackend/ContainerBackend.swift` (add to the "Volumes / networks / registries / machines / builder" MARK section, after `listNetworks()` at line ~129)
- Modify: `Sources/CapsuleBackend/MockBackend.swift` (stored `dnsDomains` + init param; recording props; nine methods in the volumes/networks section ~360)
- Modify: `Sources/CapsuleCLIBackend/CLIContainerBackend.swift` (nine methods in the volumes/networks section ~262)
- Modify: `Tests/CapsuleUnitTests/MockBackendTests.swift` (add a volumes/networks/DNS section)
- Modify: `Tests/CapsuleUnitTests/CLIContainerBackendTests.swift` (add a volumes/networks/DNS section)

**Interfaces:**
- Consumes: `VolumeConfiguration`/`NetworkConfiguration` (1.2); `CLICommand.inspectVolume/createVolume/deleteVolumes/pruneVolumes/inspectNetwork/createNetwork/deleteNetworks/pruneNetworks/listDNSDomains` (1.3); `OutputParser.parseVolumes/parseNetworks/parseDNS` (1.4); `DNSDomainSummary`, enriched summaries (1.4); existing `PruneResult`, `Parsed`, `CommandResult.isSuccess`, `runChecked`, `parsePruneResult`.
- Produces (on the protocol, both adapters):
  - `func inspectVolume(names: [String]) async throws -> Parsed<[VolumeSummary]>`
  - `func createVolume(_ config: VolumeConfiguration) async throws`
  - `func deleteVolumes(names: [String]) async throws`
  - `func pruneVolumes() async throws -> PruneResult`
  - `func inspectNetwork(names: [String]) async throws -> Parsed<[NetworkSummary]>`
  - `func createNetwork(_ config: NetworkConfiguration) async throws`
  - `func deleteNetworks(names: [String]) async throws`
  - `func pruneNetworks() async throws -> PruneResult`
  - `func listDNSDomains() async throws -> [DNSDomainSummary]`
  - `MockBackend(... dnsDomains: [DNSDomainSummary] = [])` + recorders `lastCreatedVolume: VolumeConfiguration?`, `lastDeletedVolumeNames: [String]?`, `didPruneVolumes: Bool`, `lastCreatedNetwork: NetworkConfiguration?`, `lastDeletedNetworkNames: [String]?`, `didPruneNetworks: Bool`.

**Steps:**

- [ ] **Step 1: Write the failing MockBackend tests** — append to `Tests/CapsuleUnitTests/MockBackendTests.swift`:
  ```swift
      // MARK: - Volumes / networks / DNS (M8)

      func testCreateVolumeRecordsConfigAndAppendsToList() async throws {
          let backend = MockBackend()
          try await backend.createVolume(VolumeConfiguration(name: "data", size: "1G"))
          XCTAssertEqual(backend.lastCreatedVolume?.name, "data")
          XCTAssertEqual(backend.lastCreatedVolume?.size, "1G")
          let names = try await backend.listVolumes().map(\.name)
          XCTAssertTrue(names.contains("data"))
      }

      func testDeleteVolumesRemovesAndRecords() async throws {
          let backend = MockBackend(volumes: [VolumeSummary(name: "data"), VolumeSummary(name: "keep")])
          try await backend.deleteVolumes(names: ["data"])
          XCTAssertEqual(backend.lastDeletedVolumeNames, ["data"])
          let names = try await backend.listVolumes().map(\.name)
          XCTAssertEqual(names, ["keep"])
      }

      func testPruneVolumesEmptiesAndReportsReclaimed() async throws {
          let backend = MockBackend(volumes: [VolumeSummary(name: "a"), VolumeSummary(name: "b")])
          XCTAssertFalse(backend.didPruneVolumes)
          let result = try await backend.pruneVolumes()
          XCTAssertTrue(backend.didPruneVolumes)
          XCTAssertNotNil(result.reclaimedDescription)
          let remaining = try await backend.listVolumes()
          XCTAssertTrue(remaining.isEmpty)
      }

      func testInspectVolumeReturnsMatchesAndRaw() async throws {
          let backend = MockBackend(volumes: [VolumeSummary(name: "data"), VolumeSummary(name: "x")])
          let parsed = try await backend.inspectVolume(names: ["data"])
          XCTAssertEqual(parsed.value?.map(\.name), ["data"])
          XCTAssertFalse(parsed.raw.isEmpty)
      }

      func testCreateNetworkRecordsConfigAndAppends() async throws {
          let backend = MockBackend()
          try await backend.createNetwork(NetworkConfiguration(name: "app-net", subnet: "10.0.0.0/24"))
          XCTAssertEqual(backend.lastCreatedNetwork?.name, "app-net")
          let names = try await backend.listNetworks().map(\.name)
          XCTAssertTrue(names.contains("app-net"))
      }

      func testDeleteNetworksRemovesAndRecords() async throws {
          let backend = MockBackend(networks: [
              NetworkSummary(id: "app-net", name: "app-net"),
              NetworkSummary(id: "default", name: "default", isBuiltin: true),
          ])
          try await backend.deleteNetworks(names: ["app-net"])
          XCTAssertEqual(backend.lastDeletedNetworkNames, ["app-net"])
          let names = try await backend.listNetworks().map(\.name)
          XCTAssertEqual(names, ["default"])
      }

      func testPruneNetworksExcludesBuiltins() async throws {
          let backend = MockBackend(networks: [
              NetworkSummary(id: "app-net", name: "app-net"),
              NetworkSummary(id: "default", name: "default", isBuiltin: true),
          ])
          XCTAssertFalse(backend.didPruneNetworks)
          let result = try await backend.pruneNetworks()
          XCTAssertTrue(backend.didPruneNetworks)
          XCTAssertNotNil(result.reclaimedDescription)
          let names = try await backend.listNetworks().map(\.name)
          XCTAssertEqual(names, ["default"], "builtin networks survive prune")
      }

      func testListDNSDomainsReturnsSeeded() async throws {
          let backend = MockBackend(dnsDomains: [DNSDomainSummary(domain: "capsule.test")])
          let domains = try await backend.listDNSDomains()
          XCTAssertEqual(domains.map(\.domain), ["capsule.test"])
      }

      func testVolumeNetworkOpsHonourInjectedFailure() async {
          let backend = MockBackend()
          backend.failure = BackendError.nonZeroExit(command: "x", code: 1, stderr: "boom")
          do {
              try await backend.createVolume(VolumeConfiguration(name: "data"))
              XCTFail("expected the injected failure to throw")
          } catch let BackendError.nonZeroExit(_, code, _) {
              XCTAssertEqual(code, 1)
          }
      }
  ```

- [ ] **Step 2: Write the failing CLIContainerBackend tests** — append to `Tests/CapsuleUnitTests/CLIContainerBackendTests.swift`:
  ```swift
      // MARK: - M8: volumes / networks / DNS

      func testInspectVolumeDecodesFixtureAndBuildsArgvWithoutFormat() async throws {
          let stub = StubProcessRunner()
          stub.result = CommandResult(exitCode: 0, stdout: Fixture.text("volume-inspect"), stderr: "")
          let parsed = try await makeBackend(stub).inspectVolume(names: ["capsule-m8-probe"])
          XCTAssertEqual(parsed.value?.first?.name, "capsule-m8-probe")
          XCTAssertEqual(parsed.value?.first?.sizeBytes, 536_870_912)
          XCTAssertFalse(parsed.raw.isEmpty)
          XCTAssertEqual(stub.lastCall, ["volume", "inspect", "capsule-m8-probe"])
      }

      func testCreateVolumeBuildsArgvFromConfig() async throws {
          let stub = StubProcessRunner()
          try await makeBackend(stub).createVolume(
              VolumeConfiguration(name: "data", size: "1G", labels: ["env=dev"]))
          XCTAssertEqual(
              stub.lastCall, ["volume", "create", "--label", "env=dev", "-s", "1G", "data"])
      }

      func testDeleteVolumesBuildsArgv() async throws {
          let stub = StubProcessRunner()
          try await makeBackend(stub).deleteVolumes(names: ["a", "b"])
          XCTAssertEqual(stub.lastCall, ["volume", "delete", "a", "b"])
      }

      func testPruneVolumesParsesReclaimedAndOnlyNonZeroExitFails() async throws {
          let stub = StubProcessRunner()
          stub.result = CommandResult(
              exitCode: 0, stdout: "Reclaimed 3 MB in disk space\n", stderr: "noise")
          let result = try await makeBackend(stub).pruneVolumes()
          XCTAssertEqual(result.reclaimedDescription, "Reclaimed 3 MB in disk space")
          XCTAssertEqual(stub.lastCall, ["volume", "prune"])

          stub.result = CommandResult(exitCode: 1, stdout: "", stderr: "boom")
          do {
              _ = try await makeBackend(stub).pruneVolumes()
              XCTFail("expected non-zero exit to throw")
          } catch let BackendError.nonZeroExit(_, code, stderr) {
              XCTAssertEqual(code, 1)
              XCTAssertEqual(stderr, "boom")
          }
      }

      func testInspectNetworkDecodesFixtureAndBuildsArgv() async throws {
          let stub = StubProcessRunner()
          stub.result = CommandResult(exitCode: 0, stdout: Fixture.text("network-inspect"), stderr: "")
          let parsed = try await makeBackend(stub).inspectNetwork(names: ["capsule-m8-net"])
          XCTAssertEqual(parsed.value?.first?.name, "capsule-m8-net")
          XCTAssertEqual(parsed.value?.first?.isBuiltin, false)
          XCTAssertEqual(stub.lastCall, ["network", "inspect", "capsule-m8-net"])
      }

      func testCreateAndDeleteNetworkBuildArgv() async throws {
          let stub = StubProcessRunner()
          let backend = makeBackend(stub)
          try await backend.createNetwork(NetworkConfiguration(name: "app-net", subnet: "10.0.0.0/24"))
          XCTAssertEqual(stub.lastCall, ["network", "create", "--subnet", "10.0.0.0/24", "app-net"])
          try await backend.deleteNetworks(names: ["app-net"])
          XCTAssertEqual(stub.lastCall, ["network", "delete", "app-net"])
      }

      func testPruneNetworksParsesReclaimed() async throws {
          let stub = StubProcessRunner()
          stub.result = CommandResult(exitCode: 0, stdout: "Reclaimed 0 B in disk space", stderr: "")
          let result = try await makeBackend(stub).pruneNetworks()
          XCTAssertEqual(result.reclaimedDescription, "Reclaimed 0 B in disk space")
          XCTAssertEqual(stub.lastCall, ["network", "prune"])
      }

      func testListDNSDomainsDecodesFixtureAndBuildsArgv() async throws {
          let stub = StubProcessRunner()
          stub.result = CommandResult(exitCode: 0, stdout: Fixture.text("dns-ls"), stderr: "")
          let domains = try await makeBackend(stub).listDNSDomains()
          XCTAssertEqual(domains.map(\.domain), ["capsule.test"])
          XCTAssertEqual(domains.first?.localhostIP, "127.0.0.1")
          XCTAssertEqual(stub.lastCall, ["system", "dns", "list", "--format", "json"])
      }
  ```

- [ ] **Step 3: Run; expect FAIL.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CLIContainerBackendTests`
  Expected FAIL: compile errors — `value of type 'CLIContainerBackend' has no member 'inspectVolume'` (and the same for `MockBackend` once the protocol requirement is added, since neither adapter conforms yet).

- [ ] **Step 4: Add the protocol requirements** — in `Sources/CapsuleBackend/ContainerBackend.swift`, insert after `func listNetworks() async throws -> [NetworkSummary]`:
  ```swift
      // MARK: Volume mutation / inspection (M8)

      /// Inspects one or more volumes, retaining the raw payload alongside the decoded rows.
      func inspectVolume(names: [String]) async throws -> Parsed<[VolumeSummary]>

      /// Creates a volume from a typed configuration.
      func createVolume(_ config: VolumeConfiguration) async throws

      /// Deletes one or more volumes by name (the CLI has no `--force`).
      func deleteVolumes(names: [String]) async throws

      /// Removes volumes with no container references; returns the reclaimed summary.
      func pruneVolumes() async throws -> PruneResult

      // MARK: Network mutation / inspection (M8)

      /// Inspects one or more networks, retaining the raw payload alongside the decoded rows.
      func inspectNetwork(names: [String]) async throws -> Parsed<[NetworkSummary]>

      /// Creates a network from a typed configuration.
      func createNetwork(_ config: NetworkConfiguration) async throws

      /// Deletes one or more networks by name (the CLI has no `--force`).
      func deleteNetworks(names: [String]) async throws

      /// Removes networks with no connections; returns the reclaimed summary.
      func pruneNetworks() async throws -> PruneResult

      // MARK: DNS (M8 — list only; create/delete are privileged via the sudo Terminal handoff)

      /// Lists local DNS domains (`system dns list`; no privilege required).
      func listDNSDomains() async throws -> [DNSDomainSummary]
  ```

- [ ] **Step 5: Implement on `MockBackend`.** Add a stored property beside the others (after `private var machines`):
  ```swift
      private var dnsDomains: [DNSDomainSummary]
  ```
  Add the recorders near the other `last*` recorders:
  ```swift
      /// The configuration of the most recent `createVolume` call.
      public private(set) var lastCreatedVolume: VolumeConfiguration?
      /// The names of the most recent `deleteVolumes` call.
      public private(set) var lastDeletedVolumeNames: [String]?
      /// Whether `pruneVolumes` has been invoked.
      public private(set) var didPruneVolumes = false
      /// The configuration of the most recent `createNetwork` call.
      public private(set) var lastCreatedNetwork: NetworkConfiguration?
      /// The names of the most recent `deleteNetworks` call.
      public private(set) var lastDeletedNetworkNames: [String]?
      /// Whether `pruneNetworks` has been invoked.
      public private(set) var didPruneNetworks = false
  ```
  Add the init parameter (appended last, after `sampleStats`) and its assignment:
  ```swift
          sampleStats: [ContainerStatsSample] = MockBackend.sampleStatsDefault,
          dnsDomains: [DNSDomainSummary] = []
      ) {
          // …existing assignments…
          self.sampleStats = sampleStats
          self.dnsDomains = dnsDomains
      }
  ```
  Add the methods in the "Volumes / networks / registries / machines / builder" section (after `listNetworks`):
  ```swift
      public func inspectVolume(names: [String]) async throws -> Parsed<[VolumeSummary]> {
          try withState { state in
              let matches = state.volumes.filter { names.contains($0.name) }
              return Parsed(value: matches, raw: "\(matches)")
          }
      }

      public func createVolume(_ config: VolumeConfiguration) async throws {
          try withState { state in
              state.lastCreatedVolume = config
              if !state.volumes.contains(where: { $0.name == config.name }) {
                  state.volumes.append(VolumeSummary(name: config.name))
              }
          }
      }

      public func deleteVolumes(names: [String]) async throws {
          try withState { state in
              state.lastDeletedVolumeNames = names
              state.volumes.removeAll { names.contains($0.name) }
          }
      }

      public func pruneVolumes() async throws -> PruneResult {
          try withState { state in
              let removed = state.volumes.count
              state.didPruneVolumes = true
              state.volumes.removeAll()
              return PruneResult(
                  reclaimedDescription: "Reclaimed \(removed) volume(s).", raw: "")
          }
      }

      public func inspectNetwork(names: [String]) async throws -> Parsed<[NetworkSummary]> {
          try withState { state in
              let matches = state.networks.filter { names.contains($0.name) }
              return Parsed(value: matches, raw: "\(matches)")
          }
      }

      public func createNetwork(_ config: NetworkConfiguration) async throws {
          try withState { state in
              state.lastCreatedNetwork = config
              if !state.networks.contains(where: { $0.name == config.name }) {
                  state.networks.append(
                      NetworkSummary(id: config.name, name: config.name, subnet: config.subnet))
              }
          }
      }

      public func deleteNetworks(names: [String]) async throws {
          try withState { state in
              state.lastDeletedNetworkNames = names
              state.networks.removeAll { names.contains($0.name) }
          }
      }

      public func pruneNetworks() async throws -> PruneResult {
          try withState { state in
              let removable = state.networks.filter { !$0.isBuiltin }.count
              state.didPruneNetworks = true
              state.networks.removeAll { !$0.isBuiltin }
              return PruneResult(
                  reclaimedDescription: "Reclaimed \(removable) network(s).", raw: "")
          }
      }

      public func listDNSDomains() async throws -> [DNSDomainSummary] {
          try withState { $0.dnsDomains }
      }
  ```

- [ ] **Step 6: Implement on `CLIContainerBackend`.** Add in the "Volumes / networks / registries / machines / builder" section (after `listNetworks`):
  ```swift
      public func inspectVolume(names: [String]) async throws -> Parsed<[VolumeSummary]> {
          let output = try await runChecked(CLICommand.inspectVolume(names: names))
          let value = try? OutputParser.parseVolumes(Data(output.stdout.utf8))
          return Parsed(value: value, raw: output.stdout)
      }

      public func createVolume(_ config: VolumeConfiguration) async throws {
          _ = try await runChecked(CLICommand.createVolume(config))
      }

      public func deleteVolumes(names: [String]) async throws {
          _ = try await runChecked(CLICommand.deleteVolumes(names: names))
      }

      public func pruneVolumes() async throws -> PruneResult {
          // Like `pruneContainers`: prune exits 0 and prints a human "Reclaimed …" line, so a
          // non-empty stderr is not a failure — only a non-zero exit is a real error.
          let result = try await runner.run(CLICommand.pruneVolumes(), environment: [:])
          guard result.isSuccess else {
              throw BackendError.nonZeroExit(
                  command: "container volume prune", code: result.exitCode, stderr: result.stderr)
          }
          return OutputParser.parsePruneResult(stdout: result.stdout, stderr: result.stderr)
      }

      public func inspectNetwork(names: [String]) async throws -> Parsed<[NetworkSummary]> {
          let output = try await runChecked(CLICommand.inspectNetwork(names: names))
          let value = try? OutputParser.parseNetworks(Data(output.stdout.utf8))
          return Parsed(value: value, raw: output.stdout)
      }

      public func createNetwork(_ config: NetworkConfiguration) async throws {
          _ = try await runChecked(CLICommand.createNetwork(config))
      }

      public func deleteNetworks(names: [String]) async throws {
          _ = try await runChecked(CLICommand.deleteNetworks(names: names))
      }

      public func pruneNetworks() async throws -> PruneResult {
          let result = try await runner.run(CLICommand.pruneNetworks(), environment: [:])
          guard result.isSuccess else {
              throw BackendError.nonZeroExit(
                  command: "container network prune", code: result.exitCode, stderr: result.stderr)
          }
          return OutputParser.parsePruneResult(stdout: result.stdout, stderr: result.stderr)
      }

      public func listDNSDomains() async throws -> [DNSDomainSummary] {
          let output = try await runChecked(CLICommand.listDNSDomains())
          return try OutputParser.parseDNS(Data(output.stdout.utf8))
      }
  ```

- [ ] **Step 7: Run; expect PASS.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter MockBackendTests`
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CLIContainerBackendTests`
  Then `make build` to confirm the package compiles (all conformers satisfy the protocol). Expected: all pass; build succeeds.

- [ ] **Step 8: Commit.**
  ```bash
  make format
  git add Sources/CapsuleBackend/ContainerBackend.swift \
          Sources/CapsuleBackend/MockBackend.swift \
          Sources/CapsuleCLIBackend/CLIContainerBackend.swift \
          Tests/CapsuleUnitTests/MockBackendTests.swift \
          Tests/CapsuleUnitTests/CLIContainerBackendTests.swift
  git commit -m "feat(m8): backend volume/network inspect+create+delete+prune + dns list

Nine new ContainerBackend methods on both adapters: volume/network
inspect/create/delete/prune (prune -> PruneResult, only non-zero exit fails) and
the unprivileged listDNSDomains. MockBackend seeds dnsDomains and records last
create/delete configs + prune flags (lastCreatedVolume/lastDeletedVolumeNames/
didPruneVolumes and the network equivalents); builtins survive network prune.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
  ```

---

### Task 1.6: ErrorNormalizer administrator-signature detection (sole owner)

Add the `(try sudo?)` / `must run as an administrator` → `permissionRequired(.administrator)` mapping, evaluated **before** the daemon check inside the `.nonZeroExit` case (so an admin hint wins even when daemon-ish words also appear). This is the in-process safety net for the privileged DNS path. **Phase 1 Task 1.6 is the sole owner of `Sources/CapsuleDiagnostics/ErrorNormalization.swift`'s administrator mapping** — no other phase edits this file; Phase 5 only *consumes* the resulting `permissionRequired(.administrator)` in `DNSModel`. The tests are appended to the project's existing `ErrorNormalizerTests` class (the `ErrorNormalization` test class), extending it rather than introducing a new one, and they must land before any downstream consumer.

**Files:**
- Modify: `Sources/CapsuleDiagnostics/ErrorNormalization.swift` (add `administratorSignatures` + `hasAdministratorSignature`; branch in `.nonZeroExit`)
- Modify: `Tests/CapsuleUnitTests/ErrorNormalizerTests.swift` (append an administrator-signature section to the existing `final class ErrorNormalizerTests`)

**Interfaces:**
- Consumes: `BackendError.nonZeroExit(command:code:stderr:)`, `CapsuleError.permissionRequired(kind:message:)`, `PermissionKind.administrator`, `RecoveryAction.grantPermission` (all existing).
- Produces: `ErrorNormalizer.normalize` mapping admin-gated failures to `.permissionRequired(kind: .administrator, message:)`; `detail` title `"Administrator access required"` with `recoveryActions [.grantPermission(.administrator), .openLogs]`.

**Steps:**

- [ ] **Step 1: Write the failing tests** — append to the existing `final class ErrorNormalizerTests` in `Tests/CapsuleUnitTests/ErrorNormalizerTests.swift`:
  ```swift
      // MARK: - Administrator signature mapping (M8)

      func testSudoHintBecomesPermissionRequiredAdministrator() {
          let error = BackendError.nonZeroExit(
              command: "container system dns create capsule.test", code: 1,
              stderr: "Error: cannot create domain (try sudo?)")
          guard case let .permissionRequired(kind, message) = ErrorNormalizer.normalize(error) else {
              return XCTFail("expected .permissionRequired")
          }
          XCTAssertEqual(kind, .administrator)
          XCTAssertTrue(message.contains("try sudo?"), "message preserves the CLI stderr")
      }

      func testMustRunAsAdministratorBecomesPermissionRequired() {
          let error = BackendError.nonZeroExit(
              command: "container system dns delete capsule.test", code: 1,
              stderr: "This command must run as an administrator.")
          guard case .permissionRequired(.administrator, _) = ErrorNormalizer.normalize(error) else {
              return XCTFail("expected .permissionRequired(.administrator)")
          }
      }

      func testAdministratorSignatureTakesPrecedenceOverDaemonSignature() {
          // stderr carries BOTH an admin hint and a daemon-ish word ("apiserver"); the admin
          // check runs first, so this resolves to permissionRequired, not daemonUnavailable.
          let error = BackendError.nonZeroExit(
              command: "container system dns create capsule.test", code: 1,
              stderr: "apiserver: cannot create domain (try sudo?)")
          guard case .permissionRequired(.administrator, _) = ErrorNormalizer.normalize(error) else {
              return XCTFail("admin signature must win over the daemon signature")
          }
      }

      func testAdministratorPermissionDetailIsActionable() {
          let error = BackendError.nonZeroExit(
              command: "container system dns create capsule.test", code: 1,
              stderr: "Error: cannot create domain (try sudo?)")
          let detail = ErrorNormalizer.detail(for: error)
          XCTAssertEqual(detail.title, "Administrator access required")
          XCTAssertTrue(detail.recoveryActions.contains(.grantPermission(.administrator)))
      }

      func testEmptyAdminStderrFallsBackToDefaultMessage() {
          let error = BackendError.nonZeroExit(
              command: "container system dns create capsule.test (try sudo?)", code: 1, stderr: "")
          guard case let .permissionRequired(.administrator, message) = ErrorNormalizer.normalize(
              error)
          else {
              return XCTFail("expected .permissionRequired(.administrator) from the command hint")
          }
          XCTAssertEqual(message, "This operation requires administrator privileges.")
      }
  ```

- [ ] **Step 2: Run; expect FAIL.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ErrorNormalizerTests/testSudoHintBecomesPermissionRequiredAdministrator`
  Expected FAIL: assertion `expected .permissionRequired` (today the `(try sudo?)` stderr has no daemon signature, so it normalizes to `.commandFailed`).

- [ ] **Step 3: Implement** — in `Sources/CapsuleDiagnostics/ErrorNormalization.swift`, add the signature array + helper after `hasDaemonSignature`:
  ```swift
      /// Substrings in a backend's stderr (or command) that signal the operation requires
      /// administrator privileges (e.g. `system dns create/delete`). The CLI prints
      /// `(try sudo?)` on a privileged-command failure, and its help reads "must run as an
      /// administrator". Checked AHEAD of the daemon signatures so an admin-gated failure maps
      /// to a clean permission prompt rather than a generic outage.
      private static let administratorSignatures = [
          "try sudo?",
          "must run as an administrator",
      ]

      private static func hasAdministratorSignature(_ text: String) -> Bool {
          let lowered = text.lowercased()
          return administratorSignatures.contains { lowered.contains($0) }
      }
  ```
  Then, in `normalizeBackendError`, replace the `.nonZeroExit` case body so the admin check runs first:
  ```swift
          case let .nonZeroExit(command, code, stderr):
              if hasAdministratorSignature(stderr) || hasAdministratorSignature(command) {
                  let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                  return .permissionRequired(
                      kind: .administrator,
                      message: trimmed.isEmpty
                          ? "This operation requires administrator privileges." : trimmed
                  )
              }
              if hasDaemonSignature(stderr) || hasDaemonSignature(command) {
                  let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                  return .daemonUnavailable(
                      message: trimmed.isEmpty
                          ? "The container service is not reachable." : trimmed,
                      recovery: [.startServices, .openLogs, .exportDiagnostics]
                  )
              }
              return .commandFailed(
                  command: command.split(separator: " ").map(String.init),
                  exitCode: code,
                  stderr: stderr
              )
  ```

- [ ] **Step 4: Run; expect PASS.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ErrorNormalizerTests`
  Expected: all pass (new admin tests + existing daemon/command tests unaffected — none of their stderr/command strings contain the admin signatures).

- [ ] **Step 5: Run the full suite + checks to close out Phase 1.**
  `make ci`
  Expected: build + lint + arch guard + license headers + all tests pass. (The arch guard is satisfied: `CapsuleDomain` gains nothing here; the new `*Configuration` types live in `CapsuleBackend`.)

- [ ] **Step 6: Commit.**
  ```bash
  make format
  git add Sources/CapsuleDiagnostics/ErrorNormalization.swift \
          Tests/CapsuleUnitTests/ErrorNormalizerTests.swift
  git commit -m "feat(m8): normalize administrator signatures to permissionRequired

(try sudo?) and \"must run as an administrator\" in stderr/command map to
permissionRequired(.administrator) ahead of the daemon check — the in-process
safety net for the sudo-gated DNS create/delete path. Phase 1 is the sole owner
of this ErrorNormalization mapping; Phase 5 only consumes it.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
  ```

---


---

## Phase 2: Container attachment data + attachment index + CIDR (pure domain)

This phase surfaces the raw attachment data the CLI already emits on `container list -a` and builds the pure, fully-tested domain primitives behind M8's attachment cross-reference (§5.5) and subnet-conflict detection (§5.6). It first **captures a real `containers-with-mounts.json` fixture** and pins the exact JSON keys against it (fulfilling spec §2's "the exact volume-mount shape is pinned with a real fixture" — reassigned to Phase 2 per the ownership rules); then it extends `CLIContainerRecord.Configuration` (decode `mounts[].source` + `networks[].network`), `OutputParser.parseContainers`, the `ContainerSummary` value type, and the domain `Container` with two new defaulted fields `volumeMounts: [String]` / `networkNames: [String]`; then it builds the pure `ContainerAttachmentInfo`, `AttachmentIndex`, and `CIDR` types on top of it.

It **consumes** the *existing* `OutputParser.parseContainers(_:)`, `ContainerSummary.init(id:name:image:state:ip:createdAt:)`, the lenient `lossyList(_:decode:)`, `Container(summary:)`, `Container.parseDate(_:)`, and the test-side `Fixture.data(_:)` helper + the `.copy("Fixtures")` bundling. It **produces**, for later phases: the committed `containers-with-mounts.json` fixture; `ContainerSummary.volumeMounts/networkNames`; `Container.volumeMounts/networkNames`; `ContainerAttachmentInfo`; `AttachmentIndex.build(from:)` + `containers(forVolume:)`/`containers(forNetwork:)` (consumed by Phase 4/5 browser models to stamp `attachedContainers`/`connectedContainers` and by the confirmation builders of §4.14); and `CIDR.parse(_:)` / `CIDR.overlaps(_:_:)` (consumed by `NetworkValidation.subnetConflict` in §4.13).

> This phase owns the **CONTAINER** wire-model/parser changes and the `ContainerSummary` + domain `Container` attachment fields (Phase 1 explicitly does NOT touch `parseContainers` or the container fixture). Phase 1 owns the volume/network/dns backend + their fixtures.

### Task 2.1: Capture the real `containers-with-mounts.json` fixture

This is a data-prep task (no Swift): create throwaway resources, capture a real `container list -a --format json` of a container mounting a named volume and attached to a user network, pin it as a fixture, document provenance, then delete the throwaway resources. It produces the fixture that Task 2.2's parse test pins against.

**Files:**
- Create `Tests/CapsuleUnitTests/Fixtures/containers-with-mounts.json` (real capture, auto-bundled by the test target's existing `resources: [.copy("Fixtures")]` — no `Package.swift` change)
- Modify `Tests/CapsuleUnitTests/Fixtures/README.md` (add a provenance row)

**Interfaces:**
- Produces: the `containers-with-mounts.json` fixture, readable in tests via `Fixture.data("containers-with-mounts")`. It must contain at least one element whose `configuration.id == "capsule-fx"`, with `configuration.mounts[].source == "capsule-fx-vol"` and `configuration.networks[].network == "capsule-fx-net"`.

> Prerequisite: the container system is running with a Linux kernel image available (the same prerequisite as the M5 live smoke). The capture runs the real CLI; it is not a unit test, so there is no RED/GREEN cycle.

**Steps:**

- [ ] **Step 1: Create the throwaway resources.** Run:
  ```bash
  container volume create capsule-fx-vol
  container network create capsule-fx-net --subnet 10.88.0.0/24
  container run -d --name capsule-fx \
      -v capsule-fx-vol:/data \
      --network capsule-fx-net \
      docker.io/library/alpine:latest sleep 600
  ```
  Expected: the volume and network are created, and `run -d` prints the new container id (the container stays up via `sleep 600` long enough to capture). The `10.88.0.0/24` subnet is deliberately disjoint from the builtin `default` (`192.168.64.0/24`), so creation does not conflict.

- [ ] **Step 2: Capture and pin the fixture (filtered to the throwaway container).** Run:
  ```bash
  container list -a --format json \
      | jq '[.[] | select(.configuration.id == "capsule-fx")]' \
      > Tests/CapsuleUnitTests/Fixtures/containers-with-mounts.json
  ```
  This keeps the fixture deterministic (a single, known element) regardless of any other containers present on the machine, while remaining a real capture. If `jq` is unavailable, capture the full `container list -a --format json` instead — the Task 2.2 test selects the `capsule-fx` row by name, so an unfiltered multi-container capture still passes.

- [ ] **Step 3: Verify the pinned keys are actually present.** Run:
  ```bash
  jq -e '.[] | select(.configuration.id=="capsule-fx")
              | (.configuration.mounts[0].source == "capsule-fx-vol")
                and (any(.configuration.networks[]; .network == "capsule-fx-net"))' \
      Tests/CapsuleUnitTests/Fixtures/containers-with-mounts.json
  ```
  Expected: prints `true` and exits 0. If it prints `false` / errors, the capture is missing the keys — do NOT proceed (the whole point of the fixture is to pin real keys).

- [ ] **Step 4: Delete the throwaway resources.** Run (order matters — the container holds refs to the volume and network):
  ```bash
  container stop capsule-fx || true
  container delete capsule-fx || true
  container network delete capsule-fx-net || true
  container volume delete capsule-fx-vol || true
  ```
  Expected: the throwaway container, network, and volume are gone; `container list -a`, `container network list`, and `container volume list` no longer show them.

- [ ] **Step 5: Document provenance in the Fixtures README.** Append a row to the table in `Tests/CapsuleUnitTests/Fixtures/README.md`, after the `containers-ls.json` row:
  ```markdown
  | `containers-with-mounts.json` | **Real capture** — `container list -a --format json` of a throwaway container (`capsule-fx`) mounting a named volume (`capsule-fx-vol`) and attached to a user network (`capsule-fx-net`), filtered with `jq` to that single container; the throwaway volume/network/container were deleted immediately after capture. Pins the `configuration.mounts[].source` / `configuration.networks[].network` keys behind the M8 attachment cross-reference (§5.5). |
  ```

- [ ] **Step 6: Commit.**
  ```bash
  git add Tests/CapsuleUnitTests/Fixtures/containers-with-mounts.json \
          Tests/CapsuleUnitTests/Fixtures/README.md
  git commit -m "test(m8): capture real containers-with-mounts fixture for attachment keys

Real \`container list -a --format json\` capture of a throwaway container mounting a
named volume and attached to a user network, filtered to that container, used to pin
configuration.mounts[].source and configuration.networks[].network — the M8 attachment
cross-reference source. Throwaway volume/network/container deleted after capture.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
  ```

### Task 2.2: Surface configured mounts/networks through the wire model, parser, and `ContainerSummary`

**Files:**
- Modify `Sources/CapsuleBackend/BackendValueTypes.swift` (`ContainerSummary`, lines 23–44)
- Modify `Sources/CapsuleCLIBackend/WireModels.swift` (`CLIContainerRecord.Configuration`, lines 56–64)
- Modify `Sources/CapsuleCLIBackend/OutputParser.swift` (`parseContainers`, lines 71–82)
- Modify `Tests/CapsuleUnitTests/OutputParserTests.swift` (add two tests under the `// MARK: - Containers` section)

**Interfaces:**
- Consumes: `OutputParser.parseContainers(_ data: Data) throws -> [ContainerSummary]`; `ContainerSummary.init(id:name:image:state:ip:createdAt:)`; the lenient decode path `lossyList(_:decode:)`; the `containers-with-mounts.json` fixture from Task 2.1 via `Fixture.data("containers-with-mounts")`.
- Produces:
  ```swift
  // ContainerSummary gains (appended LAST, both defaulted):
  public var volumeMounts: [String]   // default []  (configuration.mounts[].source, non-nil)
  public var networkNames: [String]   // default []  (configuration.networks[].network)
  // init gains:  volumeMounts: [String] = [], networkNames: [String] = []
  // CLIContainerRecord.Configuration gains:
  //   struct ConfiguredMount: Decodable { let source: String? };   let mounts: [ConfiguredMount]?
  //   struct ConfiguredNetwork: Decodable { let network: String? }; let networks: [ConfiguredNetwork]?
  ```

**Steps:**

- [ ] **Step 1: Write the failing tests.** Add to `Tests/CapsuleUnitTests/OutputParserTests.swift`, immediately after `testParseContainersExtractsCreationDate()`:
  ```swift
  func testParseContainersPopulatesVolumeMountsAndNetworkNames() throws {
      // Pins the real JSON keys against containers-with-mounts.json — a real
      // `container list -a --format json` capture of a container mounting a named
      // volume and attached to a user network (see Fixtures/README.md). `.contains`
      // (not exact equality) keeps the assertion robust to the runtime's exact
      // attachment order/set while still proving the keys decode.
      let rows = try OutputParser.parseContainers(Fixture.data("containers-with-mounts"))
      let fx = try XCTUnwrap(
          rows.first(where: { $0.name == "capsule-fx" }),
          "the throwaway capsule-fx container must be present in the fixture")
      XCTAssertTrue(
          fx.volumeMounts.contains("capsule-fx-vol"),
          "configuration.mounts[].source must map to volumeMounts; got \(fx.volumeMounts)")
      XCTAssertTrue(
          fx.networkNames.contains("capsule-fx-net"),
          "configuration.networks[].network must map to networkNames; got \(fx.networkNames)")
  }

  func testParseContainersDefaultsAttachmentsToEmptyWhenAbsent() throws {
      let json = """
          [{"id":"abc","configuration":{"id":"web",\
          "image":{"reference":"r"}},\
          "status":{"state":"running","networks":[]}}]
          """
      let rows = try OutputParser.parseContainers(Data(json.utf8))
      let row = try XCTUnwrap(rows.first)
      XCTAssertEqual(row.volumeMounts, [])
      XCTAssertEqual(row.networkNames, [])
  }
  ```

- [ ] **Step 2: Run it and confirm RED.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OutputParserTests`
  Expected FAIL — a compile error, because the field does not exist yet:
  `error: value of type 'ContainerSummary' has no member 'volumeMounts'`.

- [ ] **Step 3: Extend `ContainerSummary`.** Replace the struct in `Sources/CapsuleBackend/BackendValueTypes.swift` (lines 23–44) with:
  ```swift
  public struct ContainerSummary: Sendable, Equatable, Identifiable, Codable {
      public var id: String
      public var name: String
      public var image: String
      public var state: String
      /// The container's primary IPv4 address (without CIDR suffix), if attached.
      public var ip: String?
      /// The container's creation timestamp as the raw ISO-8601 string the CLI emits.
      public var createdAt: String?
      /// The `source` of each `configuration.mounts[]` entry (named-volume mounts), used to
      /// cross-reference volumes against the containers using them. Empty when unmounted.
      public var volumeMounts: [String]
      /// The `network` of each `configuration.networks[]` entry, used to cross-reference
      /// networks against the containers connected to them.
      public var networkNames: [String]

      public init(
          id: String, name: String, image: String, state: String,
          ip: String? = nil, createdAt: String? = nil,
          volumeMounts: [String] = [], networkNames: [String] = []
      ) {
          self.id = id
          self.name = name
          self.image = image
          self.state = state
          self.ip = ip
          self.createdAt = createdAt
          self.volumeMounts = volumeMounts
          self.networkNames = networkNames
      }
  }
  ```

- [ ] **Step 4: Extend the wire model.** Replace `CLIContainerRecord.Configuration` in `Sources/CapsuleCLIBackend/WireModels.swift` (lines 56–64) with:
  ```swift
      struct Configuration: Decodable {
          let id: String
          let image: ImageDescription
          let creationDate: String?
          // The CLI lists *configured* attachments here — the cross-reference source.
          // `mounts[].source` is a named volume; the configured `networks[].network` is the
          // network NAME (distinct from `Status.Attachment`, which carries addresses, not names).
          let mounts: [ConfiguredMount]?
          let networks: [ConfiguredNetwork]?

          struct ImageDescription: Decodable {
              let reference: String
          }

          struct ConfiguredMount: Decodable {
              let source: String?
          }

          struct ConfiguredNetwork: Decodable {
              let network: String?
          }
      }
  ```

- [ ] **Step 5: Populate them in the parser.** Replace `parseContainers` in `Sources/CapsuleCLIBackend/OutputParser.swift` (lines 71–82) with:
  ```swift
      public static func parseContainers(_ data: Data) throws -> [ContainerSummary] {
          try lossyList(data, decode: CLIContainerRecord.self).map { record in
              ContainerSummary(
                  id: record.id,
                  name: record.configuration.id,
                  image: record.configuration.image.reference,
                  state: record.status.state,
                  ip: record.status.networks.lazy.compactMap(\.ipAddress).first,
                  createdAt: record.configuration.creationDate,
                  volumeMounts: (record.configuration.mounts ?? []).compactMap(\.source),
                  networkNames: (record.configuration.networks ?? []).compactMap(\.network)
              )
          }
      }
  ```

- [ ] **Step 6: Run it and confirm GREEN.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OutputParserTests`
  Expected PASS — both new tests pass (the real fixture proves `configuration.mounts[].source` → `volumeMounts` and `configuration.networks[].network` → `networkNames`); the pre-existing `testParsesContainerListIntoRows` / `testParsesEmptyContainerList` / `testSkipsMalformedContainerRowsInsteadOfFailingWholeList` still pass because `mounts`/`networks` are optional and default to `[]` when absent.

- [ ] **Step 7: Commit.**
  ```bash
  git add Sources/CapsuleBackend/BackendValueTypes.swift \
          Sources/CapsuleCLIBackend/WireModels.swift \
          Sources/CapsuleCLIBackend/OutputParser.swift \
          Tests/CapsuleUnitTests/OutputParserTests.swift
  git commit -m "feat(m8): surface configured container mounts/networks on ContainerSummary

Decode configuration.mounts[].source and configuration.networks[].network from
container list -a and carry them on ContainerSummary as defaulted volumeMounts/
networkNames — the source data for the M8 attachment cross-reference. Keys are pinned
against the real containers-with-mounts.json capture.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
  ```

### Task 2.3: Mirror `volumeMounts`/`networkNames` onto the domain `Container`

**Files:**
- Modify `Sources/CapsuleDomain/Resource.swift` (`Container` struct, lines 46–68; `init(summary:)`, lines 72–81)
- Modify `Tests/CapsuleUnitTests/DomainModelTests.swift` (add two tests)

**Interfaces:**
- Consumes: `ContainerSummary.volumeMounts/networkNames` (Task 2.2); `Container(summary:)`; `Container.parseDate(_:)`.
- Produces:
  ```swift
  // Container (domain) gains (appended LAST, both defaulted):
  public var volumeMounts: [String]   // default []
  public var networkNames: [String]   // default []
  // init(summary:) maps summary.volumeMounts -> volumeMounts, summary.networkNames -> networkNames
  ```

**Steps:**

- [ ] **Step 1: Write the failing tests.** Add to `Tests/CapsuleUnitTests/DomainModelTests.swift`, after `testContainerMapsIPAndCreationDate()`:
  ```swift
  func testContainerCarriesVolumeMountsAndNetworkNames() {
      let summary = ContainerSummary(
          id: "id", name: "web", image: "nginx", state: "running",
          volumeMounts: ["data", "cache"], networkNames: ["default"])
      let container = Container(summary: summary)
      XCTAssertEqual(container.volumeMounts, ["data", "cache"])
      XCTAssertEqual(container.networkNames, ["default"])
  }

  func testContainerAttachmentsDefaultEmptyWhenSummaryHasNone() {
      let summary = ContainerSummary(id: "id", name: "n", image: "i", state: "running")
      let container = Container(summary: summary)
      XCTAssertTrue(container.volumeMounts.isEmpty)
      XCTAssertTrue(container.networkNames.isEmpty)
  }
  ```

- [ ] **Step 2: Run it and confirm RED.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DomainModelTests`
  Expected FAIL — compile error: `error: value of type 'Container' has no member 'volumeMounts'`.

- [ ] **Step 3: Extend the `Container` struct.** Replace the struct body in `Sources/CapsuleDomain/Resource.swift` (lines 46–68) with:
  ```swift
  public struct Container: Sendable, Equatable, Identifiable {
      public var id: String
      public var name: String
      public var image: String
      public var state: ContainerState
      public var ip: String?
      public var createdAt: Date?
      /// Configured volume-mount sources (`configuration.mounts[].source`), mirrored from the
      /// backend summary so the attachment index can map volumes → containers.
      public var volumeMounts: [String]
      /// Configured network names (`configuration.networks[].network`), mirrored from the
      /// backend summary so the attachment index can map networks → containers.
      public var networkNames: [String]

      public init(
          id: String, name: String, image: String, state: ContainerState,
          ip: String? = nil, createdAt: Date? = nil,
          volumeMounts: [String] = [], networkNames: [String] = []
      ) {
          self.id = id
          self.name = name
          self.image = image
          self.state = state
          self.ip = ip
          self.createdAt = createdAt
          self.volumeMounts = volumeMounts
          self.networkNames = networkNames
      }

      /// The leading 12 characters of the id, for compact display.
      public var shortID: String { String(id.prefix(12)) }
  }
  ```

- [ ] **Step 4: Map them in `init(summary:)`.** Replace `init(summary:)` in `Sources/CapsuleDomain/Resource.swift` (lines 72–81) with (preserving the doc comment on line 71):
  ```swift
      public init(summary: ContainerSummary) {
          self.init(
              id: summary.id,
              name: summary.name,
              image: summary.image,
              state: ContainerState(backendState: summary.state),
              ip: summary.ip,
              createdAt: summary.createdAt.flatMap(Container.parseDate),
              volumeMounts: summary.volumeMounts,
              networkNames: summary.networkNames
          )
      }
  ```

- [ ] **Step 5: Run it and confirm GREEN.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DomainModelTests`
  Expected PASS — both new tests pass; existing `testContainerMapsBackendSummary` / `testContainerMapsIPAndCreationDate` still pass (new fields default to `[]`).

- [ ] **Step 6: Commit.**
  ```bash
  git add Sources/CapsuleDomain/Resource.swift Tests/CapsuleUnitTests/DomainModelTests.swift
  git commit -m "feat(m8): mirror volumeMounts/networkNames onto domain Container

Carry the configured attachment slices through Container(summary:) so the pure
AttachmentIndex can derive volume/network → container maps without touching the backend.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
  ```

### Task 2.4: `ContainerAttachmentInfo` value type (input to the index)

**Files:**
- Create `Sources/CapsuleDomain/AttachmentIndex.swift`
- Create `Tests/CapsuleUnitTests/AttachmentIndexTests.swift`

**Interfaces:**
- Consumes: domain `Container` with `name`, `volumeMounts`, `networkNames` (Task 2.3).
- Produces:
  ```swift
  public struct ContainerAttachmentInfo: Sendable, Equatable {
      public var containerName: String
      public var volumeSources: [String]   // configuration.mounts[].source
      public var networkNames: [String]    // configuration.networks[].network
      public init(containerName: String, volumeSources: [String], networkNames: [String])
      public init(container: Container)     // maps name/volumeMounts/networkNames
  }
  ```

**Steps:**

- [ ] **Step 1: Write the failing tests.** Create `Tests/CapsuleUnitTests/AttachmentIndexTests.swift`:
  ```swift
  //
  //  AttachmentIndexTests.swift
  //  Capsule
  //
  //  Copyright © 2026 Capsule. All rights reserved.
  //

  import XCTest

  @testable import CapsuleDomain

  final class AttachmentIndexTests: XCTestCase {
      // MARK: - ContainerAttachmentInfo

      func testContainerAttachmentInfoMapsFromDomainContainer() {
          let container = Container(
              id: "c1", name: "web", image: "nginx", state: .running,
              volumeMounts: ["data", "cache"], networkNames: ["default"])
          let info = ContainerAttachmentInfo(container: container)
          XCTAssertEqual(info.containerName, "web")
          XCTAssertEqual(info.volumeSources, ["data", "cache"])
          XCTAssertEqual(info.networkNames, ["default"])
      }

      func testContainerAttachmentInfoMemberwiseInit() {
          let info = ContainerAttachmentInfo(
              containerName: "db", volumeSources: ["pg"], networkNames: ["backend"])
          XCTAssertEqual(info.containerName, "db")
          XCTAssertEqual(info.volumeSources, ["pg"])
          XCTAssertEqual(info.networkNames, ["backend"])
      }
  }
  ```

- [ ] **Step 2: Run it and confirm RED.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AttachmentIndexTests`
  Expected FAIL — compile error: `error: cannot find 'ContainerAttachmentInfo' in scope`.

- [ ] **Step 3: Create the file with `ContainerAttachmentInfo`.** Create `Sources/CapsuleDomain/AttachmentIndex.swift`:
  ```swift
  //
  //  AttachmentIndex.swift
  //  Capsule
  //
  //  Copyright © 2026 Capsule. All rights reserved.
  //
  //  NOTE: This module must remain free of UI and of `Foundation.Process`. The attachment
  //  index is pure data derived from `container list -a`, so it is fully unit-testable.

  import Foundation

  /// The attachment-relevant slice of a container, extracted from
  /// `container list -a --format json` (`configuration.mounts[].source` and
  /// `configuration.networks[].network`). This is the sole input to `AttachmentIndex`.
  public struct ContainerAttachmentInfo: Sendable, Equatable {
      public var containerName: String
      public var volumeSources: [String]
      public var networkNames: [String]

      public init(containerName: String, volumeSources: [String], networkNames: [String]) {
          self.containerName = containerName
          self.volumeSources = volumeSources
          self.networkNames = networkNames
      }

      /// Maps a domain `Container` (carrying `volumeMounts`/`networkNames`) into the index input.
      public init(container: Container) {
          self.init(
              containerName: container.name,
              volumeSources: container.volumeMounts,
              networkNames: container.networkNames
          )
      }
  }
  ```

- [ ] **Step 4: Run it and confirm GREEN.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AttachmentIndexTests`
  Expected PASS — both `ContainerAttachmentInfo` tests pass.

- [ ] **Step 5: Commit.**
  ```bash
  git add Sources/CapsuleDomain/AttachmentIndex.swift Tests/CapsuleUnitTests/AttachmentIndexTests.swift
  git commit -m "feat(m8): add ContainerAttachmentInfo (pure attachment-index input)

A small value type carrying containerName + configured volume sources + network names,
mappable straight from a domain Container; the sole input to AttachmentIndex.build.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
  ```

### Task 2.5: `AttachmentIndex` — build + query (volume/network → containers)

**Files:**
- Modify `Sources/CapsuleDomain/AttachmentIndex.swift` (append the `AttachmentIndex` struct after `ContainerAttachmentInfo`)
- Modify `Tests/CapsuleUnitTests/AttachmentIndexTests.swift` (add the index tests)

**Interfaces:**
- Consumes: `ContainerAttachmentInfo(containerName:volumeSources:networkNames:)` (Task 2.4).
- Produces:
  ```swift
  public struct AttachmentIndex: Sendable, Equatable {
      public let volumes: [String: [String]]    // volumeName -> [containerName]
      public let networks: [String: [String]]   // networkName -> [containerName]
      public init(volumes: [String: [String]], networks: [String: [String]])
      public func containers(forVolume name: String) -> [String]    // [] when none
      public func containers(forNetwork name: String) -> [String]   // [] when none
      public static func build(from containers: [ContainerAttachmentInfo]) -> AttachmentIndex
  }
  ```

**Steps:**

- [ ] **Step 1: Write the failing tests.** Add to `Tests/CapsuleUnitTests/AttachmentIndexTests.swift` (inside the class, after the existing methods):
  ```swift
      // MARK: - AttachmentIndex.build

      func testBuildMapsVolumesAndNetworksToContainersInInputOrder() {
          let containers = [
              ContainerAttachmentInfo(
                  containerName: "web", volumeSources: ["data"], networkNames: ["default"]),
              ContainerAttachmentInfo(
                  containerName: "api", volumeSources: ["data", "logs"],
                  networkNames: ["default", "backend"]),
          ]
          let index = AttachmentIndex.build(from: containers)
          XCTAssertEqual(index.containers(forVolume: "data"), ["web", "api"])
          XCTAssertEqual(index.containers(forVolume: "logs"), ["api"])
          XCTAssertEqual(index.containers(forNetwork: "default"), ["web", "api"])
          XCTAssertEqual(index.containers(forNetwork: "backend"), ["api"])
      }

      func testBuildWithNoAttachmentsYieldsEmptyMaps() {
          let index = AttachmentIndex.build(from: [
              ContainerAttachmentInfo(containerName: "web", volumeSources: [], networkNames: [])
          ])
          XCTAssertTrue(index.volumes.isEmpty)
          XCTAssertTrue(index.networks.isEmpty)
      }

      func testQueriesReturnEmptyArrayForUnknownNames() {
          let index = AttachmentIndex.build(from: [])
          XCTAssertEqual(index.containers(forVolume: "nope"), [])
          XCTAssertEqual(index.containers(forNetwork: "nope"), [])
      }
  ```

- [ ] **Step 2: Run it and confirm RED.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AttachmentIndexTests`
  Expected FAIL — compile error: `error: cannot find 'AttachmentIndex' in scope`.

- [ ] **Step 3: Append the `AttachmentIndex` struct.** Add to `Sources/CapsuleDomain/AttachmentIndex.swift`, after the closing brace of `ContainerAttachmentInfo`:
  ```swift

  /// A best-effort cross-reference from volumes/networks to the containers using them, built
  /// from the most recent `container list -a`. Pure: the browser models build it and stamp
  /// `attachedContainers`/`connectedContainers`, and the confirmation builders read it.
  public struct AttachmentIndex: Sendable, Equatable {
      /// `volumeName -> [containerName]`.
      public let volumes: [String: [String]]
      /// `networkName -> [containerName]`.
      public let networks: [String: [String]]

      public init(volumes: [String: [String]], networks: [String: [String]]) {
          self.volumes = volumes
          self.networks = networks
      }

      /// The containers mounting `name`, or `[]` when none.
      public func containers(forVolume name: String) -> [String] {
          volumes[name] ?? []
      }

      /// The containers connected to `name`, or `[]` when none.
      public func containers(forNetwork name: String) -> [String] {
          networks[name] ?? []
      }

      /// Folds the per-container attachment slices into the two name→containers maps,
      /// preserving the input container order within each bucket.
      public static func build(from containers: [ContainerAttachmentInfo]) -> AttachmentIndex {
          var volumes: [String: [String]] = [:]
          var networks: [String: [String]] = [:]
          for container in containers {
              for source in container.volumeSources {
                  volumes[source, default: []].append(container.containerName)
              }
              for network in container.networkNames {
                  networks[network, default: []].append(container.containerName)
              }
          }
          return AttachmentIndex(volumes: volumes, networks: networks)
      }
  }
  ```

- [ ] **Step 4: Run it and confirm GREEN.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AttachmentIndexTests`
  Expected PASS — all five `AttachmentIndexTests` methods pass.

- [ ] **Step 5: Commit.**
  ```bash
  git add Sources/CapsuleDomain/AttachmentIndex.swift Tests/CapsuleUnitTests/AttachmentIndexTests.swift
  git commit -m "feat(m8): add pure AttachmentIndex (volume/network -> containers)

build(from:) folds ContainerAttachmentInfo into volumeName->[container] and
networkName->[container] maps; containers(forVolume:)/(forNetwork:) return [] when none.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
  ```

### Task 2.6: `CIDR.parse` — IPv4 + IPv6 address/prefix parsing

**Files:**
- Create `Sources/CapsuleDomain/CIDR.swift`
- Create `Tests/CapsuleUnitTests/CIDRTests.swift`

**Interfaces:**
- Consumes: nothing (pure Foundation string work).
- Produces:
  ```swift
  public enum CIDR {
      public struct Parsed: Sendable, Equatable {
          public var bytes: [UInt8]      // 4 (IPv4) or 16 (IPv6) network-address bytes
          public var prefixLength: Int
          public var isIPv6: Bool
          public init(bytes: [UInt8], prefixLength: Int, isIPv6: Bool)
      }
      public static func parse(_ text: String) -> Parsed?            // nil on malformed
  }
  ```

**Steps:**

- [ ] **Step 1: Write the failing tests.** Create `Tests/CapsuleUnitTests/CIDRTests.swift`:
  ```swift
  //
  //  CIDRTests.swift
  //  Capsule
  //
  //  Copyright © 2026 Capsule. All rights reserved.
  //

  import XCTest

  @testable import CapsuleDomain

  final class CIDRTests: XCTestCase {
      // MARK: - parse

      func testParsesIPv4CIDR() throws {
          let parsed = try XCTUnwrap(CIDR.parse("192.168.64.0/24"))
          XCTAssertFalse(parsed.isIPv6)
          XCTAssertEqual(parsed.prefixLength, 24)
          XCTAssertEqual(parsed.bytes, [192, 168, 64, 0])
      }

      func testParsesIPv6CIDR() throws {
          let parsed = try XCTUnwrap(CIDR.parse("fdb6:5eb:8ee:85cf::/64"))
          XCTAssertTrue(parsed.isIPv6)
          XCTAssertEqual(parsed.prefixLength, 64)
          XCTAssertEqual(parsed.bytes.count, 16)
          XCTAssertEqual(Array(parsed.bytes.prefix(4)), [0xfd, 0xb6, 0x05, 0xeb])
      }

      func testParsesCompressedAndUnspecifiedIPv6() throws {
          XCTAssertEqual(try XCTUnwrap(CIDR.parse("::/0")).bytes, Array(repeating: 0, count: 16))
          let fd00 = try XCTUnwrap(CIDR.parse("fd00::/8"))
          XCTAssertEqual(Array(fd00.bytes.prefix(2)), [0xfd, 0x00])
      }

      func testParseRejectsMalformedInput() {
          XCTAssertNil(CIDR.parse("not-a-cidr"))
          XCTAssertNil(CIDR.parse("192.168.0.1"))     // no prefix
          XCTAssertNil(CIDR.parse("192.168.0.0/33"))  // IPv4 prefix too large
          XCTAssertNil(CIDR.parse("999.1.1.1/24"))    // octet out of range
          XCTAssertNil(CIDR.parse("10.0.0.0/"))       // empty prefix
          XCTAssertNil(CIDR.parse("10.0.0.0/x"))      // non-numeric prefix
          XCTAssertNil(CIDR.parse("::/200"))          // IPv6 prefix too large
          XCTAssertNil(CIDR.parse("fd00:::1/64"))     // double "::" twice
          XCTAssertNil(CIDR.parse(""))                // empty string
      }
  }
  ```

- [ ] **Step 2: Run it and confirm RED.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CIDRTests`
  Expected FAIL — compile error: `error: cannot find 'CIDR' in scope`.

- [ ] **Step 3: Create the file with `CIDR.parse`.** Create `Sources/CapsuleDomain/CIDR.swift`:
  ```swift
  //
  //  CIDR.swift
  //  Capsule
  //
  //  Copyright © 2026 Capsule. All rights reserved.
  //
  //  NOTE: This module must remain free of UI and of `Foundation.Process`. CIDR parsing and
  //  overlap detection are pure value computations used by network subnet-conflict validation.

  import Foundation

  /// Minimal CIDR support for subnet-conflict detection: parse an IPv4/IPv6 `address/prefix`
  /// string into network-address bytes, and test whether two CIDR blocks overlap.
  public enum CIDR {
      /// A parsed CIDR block: the raw network-address bytes (4 for IPv4, 16 for IPv6) and the
      /// prefix length, with the family flagged for fast same-family checks.
      public struct Parsed: Sendable, Equatable {
          public var bytes: [UInt8]
          public var prefixLength: Int
          public var isIPv6: Bool

          public init(bytes: [UInt8], prefixLength: Int, isIPv6: Bool) {
              self.bytes = bytes
              self.prefixLength = prefixLength
              self.isIPv6 = isIPv6
          }
      }

      /// Parses `"<address>/<prefix>"`, returning `nil` for anything malformed (missing or
      /// non-numeric prefix, out-of-range prefix, or an unparseable address).
      public static func parse(_ text: String) -> Parsed? {
          let trimmed = text.trimmingCharacters(in: .whitespaces)
          let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
          guard parts.count == 2, let prefix = Int(parts[1]) else { return nil }
          let address = String(parts[0])

          if let bytes = parseIPv4(address) {
              guard prefix >= 0, prefix <= 32 else { return nil }
              return Parsed(bytes: bytes, prefixLength: prefix, isIPv6: false)
          }
          if let bytes = parseIPv6(address) {
              guard prefix >= 0, prefix <= 128 else { return nil }
              return Parsed(bytes: bytes, prefixLength: prefix, isIPv6: true)
          }
          return nil
      }

      // MARK: - Address parsing

      private static func parseIPv4(_ text: String) -> [UInt8]? {
          let octets = text.split(separator: ".", omittingEmptySubsequences: false)
          guard octets.count == 4 else { return nil }
          var bytes: [UInt8] = []
          for octet in octets {
              guard let value = Int(octet), value >= 0, value <= 255 else { return nil }
              bytes.append(UInt8(value))
          }
          return bytes
      }

      private static func parseIPv6(_ text: String) -> [UInt8]? {
          let halves = text.components(separatedBy: "::")
          guard halves.count <= 2 else { return nil }

          func groups(_ part: String) -> [UInt16]? {
              if part.isEmpty { return [] }
              var result: [UInt16] = []
              for segment in part.split(separator: ":", omittingEmptySubsequences: false) {
                  guard !segment.isEmpty, segment.count <= 4,
                      let value = UInt16(segment, radix: 16)
                  else { return nil }
                  result.append(value)
              }
              return result
          }

          let all: [UInt16]
          if halves.count == 2 {
              guard let head = groups(halves[0]), let tail = groups(halves[1]) else { return nil }
              let missing = 8 - (head.count + tail.count)
              guard missing >= 1 else { return nil }
              all = head + Array(repeating: 0, count: missing) + tail
          } else {
              guard let whole = groups(text), whole.count == 8 else { return nil }
              all = whole
          }

          var bytes: [UInt8] = []
          for group in all {
              bytes.append(UInt8(group >> 8))
              bytes.append(UInt8(group & 0xff))
          }
          return bytes
      }
  }
  ```

- [ ] **Step 4: Run it and confirm GREEN.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CIDRTests`
  Expected PASS — all four parse tests pass. (`fd00:::1/64` → `parseIPv6` splits on `::` into halves `["fd00", ":1"]` (count 2, passes the `<=2` guard); then `groups(":1")` sees a leading empty segment and returns `nil` → `parse` returns `nil`. `10.0.0.0/x` → `Int("x")` is `nil` → `nil`.)

- [ ] **Step 5: Commit.**
  ```bash
  git add Sources/CapsuleDomain/CIDR.swift Tests/CapsuleUnitTests/CIDRTests.swift
  git commit -m "feat(m8): add pure CIDR.parse for IPv4 and IPv6

Parse <address>/<prefix> into network-address bytes (4 or 16) + prefix length + family,
handling :: compression and rejecting malformed/out-of-range input with nil.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
  ```

### Task 2.7: `CIDR.overlaps` — IPv4 + IPv6 overlap detection

**Files:**
- Modify `Sources/CapsuleDomain/CIDR.swift` (append an `extension CIDR` after the enum)
- Modify `Tests/CapsuleUnitTests/CIDRTests.swift` (append an `extension CIDRTests` with overlap tests)

**Interfaces:**
- Consumes: `CIDR.parse(_:) -> CIDR.Parsed?` and `CIDR.Parsed.{bytes,prefixLength,isIPv6}` (Task 2.6).
- Produces:
  ```swift
  public static func overlaps(_ lhs: String, _ rhs: String) -> Bool   // false if families differ or either malformed
  ```
  (Consumed in §4.13 by `NetworkValidation.subnetConflict(subnet:against:)`.)

**Steps:**

- [ ] **Step 1: Write the failing tests.** Append to `Tests/CapsuleUnitTests/CIDRTests.swift` (after the closing brace of `final class CIDRTests`):
  ```swift

  extension CIDRTests {
      // MARK: - overlaps

      func testOverlapTrueWhenOneContainsTheOther() {
          XCTAssertTrue(CIDR.overlaps("10.0.0.0/8", "10.1.2.0/24"))
          XCTAssertTrue(CIDR.overlaps("192.168.64.0/24", "192.168.64.128/25"))
      }

      func testIdenticalSubnetsOverlap() {
          XCTAssertTrue(CIDR.overlaps("10.0.0.0/24", "10.0.0.0/24"))
      }

      func testAdjacentIPv4SubnetsDoNotOverlap() {
          XCTAssertFalse(CIDR.overlaps("10.0.0.0/24", "10.0.1.0/24"))
      }

      func testIPv6OverlapAndNonOverlap() {
          XCTAssertTrue(CIDR.overlaps("fd00::/16", "fd00:1::/32"))
          XCTAssertFalse(CIDR.overlaps("fd00::/16", "fe00::/16"))
      }

      func testDifferentFamiliesNeverOverlap() {
          XCTAssertFalse(CIDR.overlaps("10.0.0.0/8", "fd00::/8"))
      }

      func testMalformedInputsNeverOverlap() {
          XCTAssertFalse(CIDR.overlaps("garbage", "10.0.0.0/8"))
          XCTAssertFalse(CIDR.overlaps("10.0.0.0/8", "garbage"))
          XCTAssertFalse(CIDR.overlaps("garbage", "more-garbage"))
      }
  }
  ```

- [ ] **Step 2: Run it and confirm RED.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CIDRTests`
  Expected FAIL — compile error: `error: type 'CIDR' has no member 'overlaps'`.

- [ ] **Step 3: Append the `overlaps` implementation.** Add to `Sources/CapsuleDomain/CIDR.swift`, after the closing brace of `public enum CIDR`:
  ```swift

  extension CIDR {
      /// Whether two CIDR blocks share any address. Returns `false` when the families differ
      /// or either string is malformed, so a bad input never reports a phantom conflict.
      public static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
          guard let a = parse(lhs), let b = parse(rhs), a.isIPv6 == b.isIPv6 else { return false }
          return sameNetwork(a.bytes, b.bytes, prefixBits: min(a.prefixLength, b.prefixLength))
      }

      /// Compares two equal-length address byte arrays over the leading `prefixBits` bits.
      private static func sameNetwork(_ a: [UInt8], _ b: [UInt8], prefixBits: Int) -> Bool {
          guard a.count == b.count else { return false }
          let fullBytes = prefixBits / 8
          let remainingBits = prefixBits % 8
          for index in 0..<fullBytes where a[index] != b[index] { return false }
          if remainingBits > 0 {
              let mask = UInt8(truncatingIfNeeded: 0xFF << (8 - remainingBits))
              if (a[fullBytes] & mask) != (b[fullBytes] & mask) { return false }
          }
          return true
      }
  }
  ```

- [ ] **Step 4: Run it and confirm GREEN.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CIDRTests`
  Expected PASS — all overlap tests pass: containment/identical → true; adjacent `/24`s → false (third byte differs); IPv6 `fd00::/16` ⊃ `fd00:1::/32` → true while `fe00::/16` → false; mixed families and malformed → false.

- [ ] **Step 5: Run the full pure-domain suite to confirm no regressions across the phase.**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CIDRTests` and `--filter AttachmentIndexTests` and `--filter OutputParserTests` and `--filter DomainModelTests`
  Expected PASS for all four. Optionally run `make check` to confirm the arch guard still passes (the two new Domain files import only `Foundation` and reference only `CapsuleDomain` types — no `CapsuleUI`, no `CapsuleCLIBackend`, no `Foundation.Process`).

- [ ] **Step 6: Commit.**
  ```bash
  git add Sources/CapsuleDomain/CIDR.swift Tests/CapsuleUnitTests/CIDRTests.swift
  git commit -m "feat(m8): add pure CIDR.overlaps for IPv4 and IPv6

overlaps(_:_:) compares network prefixes over min(prefix); false for differing families,
adjacent (non-containing) ranges, and malformed input. Feeds NetworkValidation subnet checks.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
  ```

---


---

## Phase 3: Volumes surface (domain + UI)

This phase delivers the complete Volumes surface: the `Volume` domain model, `VolumeBrowserModel`/`VolumeActionsModel` (synchronous create/delete/prune with a `busy` set and `LifecycleNotice`-on-failure — no Activity tasks), `VolumeDraft`/`KeyValueRow` + `validatedConfiguration` and the draft-taking `create(draft:)`/`commandPreview(for:)`/`validationMessage(_:)`/`isValid(_:)` accessors, the `.deleteVolume`/`.pruneVolumes` confirmation kinds and builders (added **additively**), the four volume views (`VolumeListView`, `VolumeInspectorView`, `CreateVolumeSheet`, `VolumePruneSheet`), and the wiring through `ContentColumnView`/`AppShellView`/`RootView`/`CapsuleScene`/`AppEnvironment` (routing + inspector arms + the `volumeActionsModel.notice` overlay, all **additive**).

It **consumes** from Phase 1 the backend pieces `VolumeSummary` (with `sizeBytes`/`options`/`labels`/`createdAt`), `VolumeConfiguration(name:size:options:labels:)`, and the backend methods `inspectVolume(names:)`/`createVolume(_:)`/`deleteVolumes(names:)`/`pruneVolumes() -> PruneResult` (plus `MockBackend` support for them); and **consumes** from Phase 2 the pure `AttachmentIndex`, `ContainerAttachmentInfo`, `ContainerSummary.volumeMounts`, and the `Container.volumeMounts` mapping. It **produces** `KeyValueRow` (reused by Phase 4's `NetworkDraft`), the `Volume` model, the two volume models, and the `.deleteVolume`/`.pruneVolumes` confirmation builders.

> **Ownership note.** Capability **gating is Phase 6's** (`SystemHealth.supports` + sidebar + the in-pane gating of the `ContentColumnView` volume/network arms + the DNS pane). Phase 3 adds **no** gating logic: `VolumeListView` exposes Create/Clean Up unconditionally, and the `.volumes` routing arm in `ContentColumnView` simply routes. The sidebar's existing `.volumes` row already gates *selectability* on `SystemFeature.volumes` (pre-existing behavior, not added here).
>
> **Additive-edit note.** Networks and DNS are **separate phases**. Phase 3 touches the shared wiring files (`Confirmation.swift`, `ContentColumnView.swift`, `AppShellView.swift`, `RootView.swift`, `CapsuleScene.swift`, `AppEnvironment.swift`) **additively** — it inserts only the volume cases/properties/arms, assuming earlier phases' additions are already present; the network/DNS phases add their own beside them. It NEVER replaces a whole switch, enum, or struct body.

---

### Task 3.1: `Volume` domain model

**Files:**
- Create: `Sources/CapsuleDomain/Volume.swift`
- Create: `Tests/CapsuleUnitTests/VolumeTests.swift`

**Interfaces:**
- Consumes (Phase 1): `VolumeSummary(name:source:sizeBytes:options:labels:createdAt:)` with `sizeBytes: Int64?`, `options: [String:String]`, `labels: [String:String]`, `createdAt: String?`.
- Consumes (existing): `Container.parseDate(_:) -> Date?` (static, in `Resource.swift`).
- Produces: `public struct Volume: Sendable, Equatable, Identifiable` with `id == name`, designated `init(name:source:sizeBytes:options:labels:createdAt:attachedContainers:)`, and `init(summary: VolumeSummary, attachedContainers: [String] = [])`.

**Steps:**

- [ ] **Step 1: Write the failing test** at `Tests/CapsuleUnitTests/VolumeTests.swift`:

```swift
//
//  VolumeTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

final class VolumeTests: XCTestCase {
    func testInitFromSummaryMapsFieldsAndParsesDate() {
        let summary = VolumeSummary(
            name: "data",
            source: "/var/lib/containers/volumes/data",
            sizeBytes: 1024,
            options: ["journaling": "on"],
            labels: ["env": "dev"],
            createdAt: "2026-06-01T00:00:00Z")

        let volume = Volume(summary: summary, attachedContainers: ["web"])

        XCTAssertEqual(volume.id, "data")
        XCTAssertEqual(volume.name, "data")
        XCTAssertEqual(volume.source, "/var/lib/containers/volumes/data")
        XCTAssertEqual(volume.sizeBytes, 1024)
        XCTAssertEqual(volume.options, ["journaling": "on"])
        XCTAssertEqual(volume.labels, ["env": "dev"])
        XCTAssertNotNil(volume.createdAt)
        XCTAssertEqual(volume.attachedContainers, ["web"])
    }

    func testInitFromSummaryWithUnparseableDateYieldsNil() {
        let volume = Volume(summary: VolumeSummary(name: "x", createdAt: "not-a-date"))
        XCTAssertNil(volume.createdAt)
        XCTAssertTrue(volume.attachedContainers.isEmpty)
    }

    func testIdIsName() {
        XCTAssertEqual(Volume(name: "cache").id, "cache")
    }
}
```

- [ ] **Step 2: Run it, expect a compile FAIL.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter VolumeTests` → fails to build: `error: cannot find 'Volume' in scope`.

- [ ] **Step 3: Write the implementation** at `Sources/CapsuleDomain/Volume.swift`:

```swift
//
//  Volume.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The domain's
//  model of a storage volume — decoupled from the backend wire format, with the attachment
//  cross-reference (`attachedContainers`) stamped by `VolumeBrowserModel` from the
//  AttachmentIndex.

import CapsuleBackend
import Foundation

/// The domain's model of a storage volume.
public struct Volume: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var source: String?
    public var sizeBytes: Int64?
    public var options: [String: String]
    public var labels: [String: String]
    public var createdAt: Date?
    /// Containers that mount this volume, derived from the AttachmentIndex (best-effort,
    /// as fresh as the last container list). Empty when nothing mounts it.
    public var attachedContainers: [String]

    public init(
        name: String,
        source: String? = nil,
        sizeBytes: Int64? = nil,
        options: [String: String] = [:],
        labels: [String: String] = [:],
        createdAt: Date? = nil,
        attachedContainers: [String] = []
    ) {
        self.name = name
        self.source = source
        self.sizeBytes = sizeBytes
        self.options = options
        self.labels = labels
        self.createdAt = createdAt
        self.attachedContainers = attachedContainers
    }
}

extension Volume {
    /// Maps a backend summary into the domain model, parsing the ISO-8601 creation date and
    /// stamping any cross-referenced attachments.
    public init(summary: VolumeSummary, attachedContainers: [String] = []) {
        self.init(
            name: summary.name,
            source: summary.source,
            sizeBytes: summary.sizeBytes,
            options: summary.options,
            labels: summary.labels,
            createdAt: summary.createdAt.flatMap(Container.parseDate),
            attachedContainers: attachedContainers)
    }
}
```

- [ ] **Step 4: Run it, expect PASS.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter VolumeTests` → 3 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/CapsuleDomain/Volume.swift Tests/CapsuleUnitTests/VolumeTests.swift
git commit -m "feat(volumes): Volume domain model mapped from VolumeSummary

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 3.2: `KeyValueRow` + `VolumeDraft`

**Files:**
- Create: `Sources/CapsuleDomain/VolumeDraft.swift`
- Create: `Tests/CapsuleUnitTests/VolumeDraftTests.swift`

**Interfaces:**
- Produces: `public struct KeyValueRow: Sendable, Equatable, Identifiable` with `id: UUID`, `key: String`, `value: String`, `init(id:key:value:)` (all defaulted), and `var token: String? { key.isEmpty ? nil : "\(key)=\(value)" }`. **Reused by Phase 4's `NetworkDraft`.**
- Produces: `public struct VolumeDraft: Sendable, Equatable` with `name: String`, `size: String`, `options: [KeyValueRow]`, `labels: [KeyValueRow]`, `init(name:size:options:labels:)` (all defaulted), and `static func isValidSize(_:) -> Bool`.

**Steps:**

- [ ] **Step 1: Write the failing test** at `Tests/CapsuleUnitTests/VolumeDraftTests.swift`:

```swift
//
//  VolumeDraftTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class VolumeDraftTests: XCTestCase {
    func testKeyValueRowTokenOmitsEmptyKey() {
        XCTAssertNil(KeyValueRow(key: "", value: "anything").token)
        XCTAssertEqual(KeyValueRow(key: "journaling", value: "on").token, "journaling=on")
        XCTAssertEqual(KeyValueRow(key: "flag", value: "").token, "flag=")
    }

    func testKeyValueRowsAreUniquelyIdentified() {
        XCTAssertNotEqual(KeyValueRow().id, KeyValueRow().id)
    }

    func testVolumeDraftDefaultsAreEmpty() {
        let draft = VolumeDraft()
        XCTAssertTrue(draft.name.isEmpty)
        XCTAssertTrue(draft.size.isEmpty)
        XCTAssertTrue(draft.options.isEmpty)
        XCTAssertTrue(draft.labels.isEmpty)
    }

    func testIsValidSizeAcceptsSuffixedNumbers() {
        XCTAssertTrue(VolumeDraft.isValidSize("10G"))
        XCTAssertTrue(VolumeDraft.isValidSize("512m"))
        XCTAssertTrue(VolumeDraft.isValidSize("1.5T"))
        XCTAssertTrue(VolumeDraft.isValidSize("100K"))
        XCTAssertTrue(VolumeDraft.isValidSize("2P"))
    }

    func testIsValidSizeRejectsMissingOrBadSuffix() {
        XCTAssertFalse(VolumeDraft.isValidSize("10"))
        XCTAssertFalse(VolumeDraft.isValidSize("G"))
        XCTAssertFalse(VolumeDraft.isValidSize("ten G"))
        XCTAssertFalse(VolumeDraft.isValidSize("10GB"))
    }
}
```

- [ ] **Step 2: Run it, expect a compile FAIL.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter VolumeDraftTests` → `error: cannot find 'KeyValueRow' in scope`.

- [ ] **Step 3: Write the implementation** at `Sources/CapsuleDomain/VolumeDraft.swift`:

```swift
//
//  VolumeDraft.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. UI-friendly drafts
//  the create sheets bind to. The model's `validatedConfiguration(_:)` turns a draft into a
//  `VolumeConfiguration` (the argv single-source-of-truth in CapsuleBackend).

import Foundation

/// A reusable advanced-options row (`key`/`value`) rendered as a `k=v` token. Shared by the
/// volume and network create sheets.
public struct KeyValueRow: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var key: String
    public var value: String

    public init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }

    /// The `key=value` token, or nil when the key is blank (a blank row is ignored).
    public var token: String? {
        key.isEmpty ? nil : "\(key)=\(value)"
    }
}

/// A UI-friendly draft of a volume to create.
public struct VolumeDraft: Sendable, Equatable {
    public var name: String
    /// Raw size, e.g. "10G". Validated against `isValidSize` before launch.
    public var size: String
    /// Driver `--opt` rows.
    public var options: [KeyValueRow]
    /// `--label` rows.
    public var labels: [KeyValueRow]

    public init(
        name: String = "", size: String = "",
        options: [KeyValueRow] = [], labels: [KeyValueRow] = []
    ) {
        self.name = name
        self.size = size
        self.options = options
        self.labels = labels
    }

    /// A size is valid only as a number (optionally fractional) followed by a single
    /// K/M/G/T/P suffix (case-insensitive) — the suffixes the CLI's `-s` accepts.
    public static func isValidSize(_ raw: String) -> Bool {
        guard let last = raw.last, "kKmMgGtTpP".contains(last) else { return false }
        let number = raw.dropLast()
        guard !number.isEmpty else { return false }
        return Double(number) != nil
    }
}
```

- [ ] **Step 4: Run it, expect PASS.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter VolumeDraftTests` → all pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/CapsuleDomain/VolumeDraft.swift Tests/CapsuleUnitTests/VolumeDraftTests.swift
git commit -m "feat(volumes): KeyValueRow + VolumeDraft with size validation

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 3.3: `VolumeBrowserModel` (+ `VolumeLoadState`, `VolumeInspection`)

**Files:**
- Create: `Sources/CapsuleDomain/VolumeBrowserModel.swift`
- Create: `Tests/CapsuleUnitTests/VolumeBrowserModelTests.swift`

**Interfaces:**
- Consumes (Task 3.1): `Volume`, `Volume.init(summary:attachedContainers:)`.
- Consumes (Phase 1): `backend.listVolumes() -> [VolumeSummary]`, `backend.inspectVolume(names:) -> Parsed<[VolumeSummary]>`.
- Consumes (Phase 2): `ContainerSummary.volumeMounts`, `AttachmentIndex.build(from:) -> AttachmentIndex`, `AttachmentIndex.containers(forVolume:) -> [String]`, `ContainerAttachmentInfo.init(container:)`, `Container.init(summary:)` mapping `volumeMounts`.
- Consumes (existing): `SystemStatusModel.defaultNormalize`, `CapsuleError`, `ErrorDetail`.
- Produces: `public enum VolumeLoadState`, `public struct VolumeInspection`, `@MainActor @Observable public final class VolumeBrowserModel` with `allVolumes`, `loadState`, `searchText`, `selection`, `rows`, `selectedVolumes`, `isEmptyButHealthy`, `noMatches`, `refresh()`, `inspect(name:)`.

**Steps:**

- [ ] **Step 1: Write the failing test** at `Tests/CapsuleUnitTests/VolumeBrowserModelTests.swift`:

```swift
//
//  VolumeBrowserModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The volumes read surface: loading (down service vs genuinely empty), search, selection,
//  attachment stamping via the AttachmentIndex, and raw-retaining inspect.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class VolumeBrowserModelTests: XCTestCase {
    func testRefreshLoadsAndStampsAttachedContainers() async {
        let backend = MockBackend(
            containers: [
                ContainerSummary(
                    id: "c1", name: "web", image: "alpine", state: "running",
                    volumeMounts: ["data"])
            ],
            volumes: [VolumeSummary(name: "data"), VolumeSummary(name: "cache")])
        let model = VolumeBrowserModel(backend: backend)

        await model.refresh()

        XCTAssertEqual(model.loadState, .loaded)
        let data = model.allVolumes.first { $0.name == "data" }
        let cache = model.allVolumes.first { $0.name == "cache" }
        XCTAssertEqual(data?.attachedContainers, ["web"])
        XCTAssertEqual(cache?.attachedContainers, [], "an unmounted volume has no attachments")
    }

    func testUnavailableIsDistinctFromEmpty() async {
        let backend = MockBackend(volumes: [])
        backend.failure = BackendError.nonZeroExit(
            command: "container volume list", code: 1, stderr: "Connection refused")
        let model = VolumeBrowserModel(backend: backend)

        await model.refresh()

        guard case .unavailable = model.loadState else {
            return XCTFail("a daemon failure must surface as .unavailable, not an empty list")
        }
        XCTAssertFalse(model.isEmptyButHealthy)
    }

    func testEmptyButHealthyWhenServiceUpButNoVolumes() async {
        let model = VolumeBrowserModel(backend: MockBackend(volumes: []))
        await model.refresh()
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertTrue(model.isEmptyButHealthy)
    }

    func testSearchMatchesNameAndSource() async {
        let backend = MockBackend(volumes: [
            VolumeSummary(name: "data", source: "/srv/data"),
            VolumeSummary(name: "cache", source: "/srv/cache"),
        ])
        let model = VolumeBrowserModel(backend: backend)
        await model.refresh()

        model.searchText = "cache"
        XCTAssertEqual(model.rows.map(\.name), ["cache"])

        model.searchText = "/srv/data"
        XCTAssertEqual(model.rows.map(\.name), ["data"], "source is searchable")
    }

    func testNoMatchesWhenSearchExcludesEverything() async {
        let model = VolumeBrowserModel(backend: MockBackend(volumes: [VolumeSummary(name: "data")]))
        await model.refresh()
        model.searchText = "zzz-not-here"
        XCTAssertTrue(model.noMatches)
        XCTAssertFalse(model.isEmptyButHealthy)
    }

    func testSelectionIsIntersectedWithLoadedRowsOnRefresh() async {
        let backend = MockBackend(volumes: [VolumeSummary(name: "data")])
        let model = VolumeBrowserModel(backend: backend)
        await model.refresh()
        model.selection = ["data", "ghost"]

        await model.refresh()

        XCTAssertEqual(model.selection, ["data"], "stale ids are dropped")
    }

    func testInspectReturnsDecodedValueAndRawPayload() async {
        let backend = MockBackend(volumes: [VolumeSummary(name: "data")])
        let model = VolumeBrowserModel(backend: backend)
        let inspection = await model.inspect(name: "data")
        XCTAssertEqual(inspection.value?.name, "data")
        XCTAssertFalse(inspection.rawJSON.isEmpty)
    }
}
```

- [ ] **Step 2: Run it, expect a compile FAIL.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter VolumeBrowserModelTests` → `error: cannot find 'VolumeBrowserModel' in scope`.

- [ ] **Step 3: Write the implementation** at `Sources/CapsuleDomain/VolumeBrowserModel.swift`:

```swift
//
//  VolumeBrowserModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The volumes read
//  surface, mirroring `ImageBrowserModel`: a loaded list with a live query (search + sort),
//  a multi-selection, and raw-retaining inspect. On refresh it also reads the container list
//  to build an AttachmentIndex and stamps each volume's `attachedContainers`. Volume actions
//  (create/delete/prune) live in `VolumeActionsModel`.

import CapsuleBackend
import Foundation
import Observation

/// The load state of the volume list, kept separate from `rows` so the UI can distinguish
/// "service unreachable" from "no volumes" from "no matches".
public enum VolumeLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case unavailable(ErrorDetail)
}

/// A volume inspection: the decoded domain value (nil if the payload drifted) paired with
/// the exact raw JSON, so the inspector can always show *something*.
public struct VolumeInspection: Sendable, Equatable {
    public var value: Volume?
    public var rawJSON: String

    public init(value: Volume?, rawJSON: String) {
        self.value = value
        self.rawJSON = rawJSON
    }
}

@MainActor
@Observable
public final class VolumeBrowserModel {
    public private(set) var allVolumes: [Volume] = []
    public private(set) var loadState: VolumeLoadState = .idle

    public var searchText: String = ""
    public var selection: Set<Volume.ID> = []

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

    /// Volumes passing the search term, ordered by name.
    public var rows: [Volume] {
        allVolumes
            .filter { matchesSearch($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public var selectedVolumes: [Volume] {
        allVolumes.filter { selection.contains($0.id) }
    }

    /// The service is up but there are genuinely no volumes.
    public var isEmptyButHealthy: Bool {
        loadState == .loaded && allVolumes.isEmpty
    }

    /// There are volumes, but the search matched none.
    public var noMatches: Bool {
        loadState == .loaded && !allVolumes.isEmpty && rows.isEmpty
    }

    private func matchesSearch(_ volume: Volume) -> Bool {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        return volume.name.localizedCaseInsensitiveContains(term)
            || (volume.source?.localizedCaseInsensitiveContains(term) ?? false)
    }

    // MARK: Loading

    public func refresh() async {
        loadState = .loading
        do {
            let summaries = try await backend.listVolumes()
            let index = await attachmentIndex()
            allVolumes = summaries.map { summary in
                Volume(
                    summary: summary,
                    attachedContainers: index.containers(forVolume: summary.name))
            }
            selection = selection.intersection(Set(allVolumes.map(\.id)))
            loadState = .loaded
            onActivity("Loaded \(allVolumes.count) volume(s).")
        } catch {
            allVolumes = []
            let detail = normalize(error).detail
            onActivity("Failed to load volumes: \(detail.title)")
            loadState = .unavailable(detail)
        }
    }

    /// Inspects one volume, mapping the backend's raw-retaining `Parsed` into the domain
    /// `VolumeInspection`. Never throws: a failure yields an empty raw payload.
    public func inspect(name: String) async -> VolumeInspection {
        do {
            let parsed = try await backend.inspectVolume(names: [name])
            return VolumeInspection(
                value: parsed.value?.first.map { Volume(summary: $0) },
                rawJSON: parsed.raw)
        } catch {
            return VolumeInspection(value: nil, rawJSON: "")
        }
    }

    /// Builds the best-effort attachment cross-reference from the current container list.
    /// A container-list failure degrades gracefully to an empty index — volumes still load.
    private func attachmentIndex() async -> AttachmentIndex {
        let containers = (try? await backend.listContainers(all: true)) ?? []
        return AttachmentIndex.build(
            from: containers.map(Container.init(summary:)).map(ContainerAttachmentInfo.init(container:)))
    }
}
```

- [ ] **Step 4: Run it, expect PASS.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter VolumeBrowserModelTests` → all pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/CapsuleDomain/VolumeBrowserModel.swift Tests/CapsuleUnitTests/VolumeBrowserModelTests.swift
git commit -m "feat(volumes): VolumeBrowserModel with attachment stamping + inspect

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 3.4: `VolumeActionsModel` (create/delete/prune + draft-facing accessors)

**Files:**
- Create: `Sources/CapsuleDomain/VolumeActionsModel.swift`
- Create: `Tests/CapsuleUnitTests/VolumeActionsModelTests.swift`

**Interfaces:**
- Consumes (Task 3.1/3.2): `Volume`, `VolumeDraft`, `VolumeDraft.isValidSize`, `KeyValueRow.token`.
- Consumes (Phase 1): `VolumeConfiguration(name:size:options:labels:)` (+ its `arguments`), `backend.createVolume(_:)`, `backend.deleteVolumes(names:)`, `backend.pruneVolumes() -> PruneResult`.
- Consumes (Phase 2): `ContainerSummary.volumeMounts`, `AttachmentIndex.build(from:)`, `ContainerAttachmentInfo.init(container:)`, `Container.init(summary:)`.
- Consumes (existing): `PruneSummary`, `LifecycleNotice`, `ConfirmationRequest`, `PruneResult.reclaimedDescription`, `ErrorNormalizer.normalize`.
- Produces: `@MainActor @Observable public final class VolumeActionsModel` with `busy`, `notice`, `confirmation`, `create(_ config:) -> Bool`, `create(draft:) -> Bool`, `delete(name:)`, `deleteAll(names:)`, `prune() -> PruneSummary`, `computePruneTargets() -> [Volume]`, `validatedConfiguration(_:) -> Result<VolumeConfiguration, CapsuleError>`, and the **Domain-primitive accessors the sheet binds to**: `commandPreview(for:) -> String`, `validationMessage(_:) -> String?`, `isValid(_:) -> Bool`.

**Steps:**

- [ ] **Step 1: Write the failing test** at `Tests/CapsuleUnitTests/VolumeActionsModelTests.swift`:

```swift
//
//  VolumeActionsModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The synchronous volume operations: create/delete/prune (busy set + LifecycleNotice on
//  failure, reloadList on success, no Activity tasks), the zero-attachment prune preview,
//  draft validation, and the Domain-primitive accessors (commandPreview / validationMessage /
//  isValid / create(draft:)) the create sheet binds to.

import CapsuleBackend
import CapsuleDiagnostics
import XCTest

@testable import CapsuleDomain

@MainActor
final class VolumeActionsModelTests: XCTestCase {
    func testCreateSucceedsReloadsAndReturnsTrue() async {
        let backend = MockBackend(volumes: [])
        var reloads = 0
        let model = VolumeActionsModel(backend: backend, reloadList: { reloads += 1 })

        let ok = await model.create(VolumeConfiguration(name: "data"))

        XCTAssertTrue(ok)
        XCTAssertEqual(reloads, 1)
        XCTAssertNil(model.notice)
        XCTAssertTrue(model.busy.isEmpty, "busy clears after the op")
    }

    func testCreateFailureSetsNoticeAndReturnsFalse() async {
        let backend = MockBackend(volumes: [])
        backend.failure = BackendError.nonZeroExit(
            command: "container volume create", code: 1, stderr: "name already in use")
        let model = VolumeActionsModel(
            backend: backend, normalize: { ErrorNormalizer.normalize($0) })

        let ok = await model.create(VolumeConfiguration(name: "data"))

        XCTAssertFalse(ok)
        XCTAssertNotNil(model.notice)
        XCTAssertTrue(model.busy.isEmpty)
    }

    func testDeleteReloadsAndClearsBusy() async {
        let backend = MockBackend(volumes: [VolumeSummary(name: "data")])
        var reloads = 0
        let model = VolumeActionsModel(backend: backend, reloadList: { reloads += 1 })

        await model.delete(name: "data")

        XCTAssertEqual(reloads, 1)
        XCTAssertNil(model.notice)
        XCTAssertTrue(model.busy.isEmpty)
    }

    func testDeleteFailureSurfacesNotice() async {
        let backend = MockBackend(volumes: [VolumeSummary(name: "data")])
        backend.failure = BackendError.nonZeroExit(
            command: "container volume delete", code: 1,
            stderr: "Error: failed to delete one or more volumes")
        let model = VolumeActionsModel(
            backend: backend, normalize: { ErrorNormalizer.normalize($0) })

        await model.delete(name: "data")

        XCTAssertNotNil(model.notice)
    }

    func testDeleteAllRunsAndReloads() async {
        let backend = MockBackend(volumes: [VolumeSummary(name: "a"), VolumeSummary(name: "b")])
        var reloads = 0
        let model = VolumeActionsModel(backend: backend, reloadList: { reloads += 1 })

        await model.deleteAll(names: ["a", "b"])

        XCTAssertEqual(reloads, 1)
        XCTAssertNil(model.notice)
    }

    func testPruneReturnsSummaryAndReloads() async {
        let backend = MockBackend(volumes: [VolumeSummary(name: "data")])
        var reloads = 0
        let model = VolumeActionsModel(backend: backend, reloadList: { reloads += 1 })

        let summary = await model.prune()

        XCTAssertFalse(summary.message.isEmpty)
        XCTAssertEqual(reloads, 1)
    }

    func testPruneFailureSetsNotice() async {
        let backend = MockBackend(volumes: [])
        backend.failure = BackendError.nonZeroExit(
            command: "container volume prune", code: 1, stderr: "boom")
        let model = VolumeActionsModel(backend: backend)

        let summary = await model.prune()

        XCTAssertNotNil(model.notice)
        XCTAssertEqual(summary.message, "Cleanup failed.")
    }

    func testComputePruneTargetsReturnsZeroAttachmentVolumes() async {
        let backend = MockBackend(
            containers: [
                ContainerSummary(
                    id: "c1", name: "web", image: "alpine", state: "running",
                    volumeMounts: ["data"])
            ],
            volumes: [VolumeSummary(name: "data"), VolumeSummary(name: "cache")])
        let model = VolumeActionsModel(backend: backend)

        let targets = await model.computePruneTargets()

        XCTAssertEqual(targets.map(\.name), ["cache"], "only unattached volumes are candidates")
    }

    func testValidatedConfigurationRequiresName() {
        let model = VolumeActionsModel(backend: MockBackend())
        guard case let .failure(error) = model.validatedConfiguration(VolumeDraft()) else {
            return XCTFail("an empty name must fail validation")
        }
        guard case let .invalidInput(field, _) = error else {
            return XCTFail("expected .invalidInput")
        }
        XCTAssertEqual(field, "name")
    }

    func testValidatedConfigurationRejectsBadSize() {
        let model = VolumeActionsModel(backend: MockBackend())
        let draft = VolumeDraft(name: "data", size: "10")
        guard case let .failure(error) = model.validatedConfiguration(draft),
            case let .invalidInput(field, _) = error
        else {
            return XCTFail("a suffixless size must fail validation")
        }
        XCTAssertEqual(field, "size")
    }

    func testValidatedConfigurationBuildsConfigWithOptionsAndLabels() {
        let model = VolumeActionsModel(backend: MockBackend())
        let draft = VolumeDraft(
            name: "data", size: "10G",
            options: [KeyValueRow(key: "journaling", value: "on"), KeyValueRow(key: "", value: "x")],
            labels: [KeyValueRow(key: "env", value: "dev")])

        guard case let .success(config) = model.validatedConfiguration(draft) else {
            return XCTFail("a valid draft must produce a configuration")
        }
        XCTAssertEqual(config.name, "data")
        XCTAssertEqual(config.size, "10G")
        XCTAssertEqual(config.options, ["journaling=on"], "blank-key rows are dropped")
        XCTAssertEqual(config.labels, ["env=dev"])
    }

    // MARK: - Domain-primitive accessors the sheet binds to

    func testCommandPreviewReflectsValidatedConfiguration() {
        let model = VolumeActionsModel(backend: MockBackend())
        let draft = VolumeDraft(
            name: "data", size: "10G",
            options: [KeyValueRow(key: "journaling", value: "on")],
            labels: [KeyValueRow(key: "env", value: "dev")])

        XCTAssertEqual(
            model.commandPreview(for: draft),
            "container volume create --label env=dev --opt journaling=on -s 10G data")
    }

    func testCommandPreviewFallsBackWhenInvalid() {
        let model = VolumeActionsModel(backend: MockBackend())
        XCTAssertEqual(model.commandPreview(for: VolumeDraft()), "container volume create")
    }

    func testValidationMessageAndIsValidTrackValidity() {
        let model = VolumeActionsModel(backend: MockBackend())
        XCTAssertNil(model.validationMessage(VolumeDraft(name: "data")))
        XCTAssertTrue(model.isValid(VolumeDraft(name: "data")))
        XCTAssertNotNil(model.validationMessage(VolumeDraft()))
        XCTAssertFalse(model.isValid(VolumeDraft()))
    }

    func testCreateFromDraftValidatesAndSucceeds() async {
        let backend = MockBackend(volumes: [])
        var reloads = 0
        let model = VolumeActionsModel(backend: backend, reloadList: { reloads += 1 })

        let ok = await model.create(draft: VolumeDraft(name: "data", size: "10G"))

        XCTAssertTrue(ok)
        XCTAssertEqual(reloads, 1)
        XCTAssertNil(model.notice)
    }

    func testCreateFromDraftSetsNoticeOnValidationFailure() async {
        let backend = MockBackend(volumes: [])
        var reloads = 0
        let model = VolumeActionsModel(backend: backend, reloadList: { reloads += 1 })

        let ok = await model.create(draft: VolumeDraft())  // empty name

        XCTAssertFalse(ok)
        XCTAssertNotNil(model.notice)
        XCTAssertEqual(reloads, 0, "a validation failure never reaches the backend")
    }
}
```

- [ ] **Step 2: Run it, expect a compile FAIL.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter VolumeActionsModelTests` → `error: cannot find 'VolumeActionsModel' in scope`.

- [ ] **Step 3: Write the implementation** at `Sources/CapsuleDomain/VolumeActionsModel.swift`:

```swift
//
//  VolumeActionsModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Owns the
//  non-streaming volume operations — create, delete (single/bulk), and prune — mirroring
//  `ImageActionsModel`. These are near-instant, so they use a `busy` set and a
//  `LifecycleNotice` on failure rather than Activity tasks. It also exposes Domain-primitive
//  accessors (commandPreview / validationMessage / isValid / create(draft:)) so the create
//  sheet can stay free of any backend `*Configuration` type — mirroring how RunModel/BuildModel
//  back QuickRunSheet/BuildSheet. The read surface lives in `VolumeBrowserModel`.

import CapsuleBackend
import Foundation
import Observation

@MainActor
@Observable
public final class VolumeActionsModel {
    public private(set) var busy: Set<String> = []
    public var notice: LifecycleNotice?
    /// A pending destructive confirmation the UI should present, or nil.
    public var confirmation: ConfirmationRequest?

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void
    private let reloadList: @MainActor () async -> Void

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in },
        reloadList: @escaping @MainActor () async -> Void = {}
    ) {
        self.backend = backend
        self.normalize = normalize
        self.onActivity = onActivity
        self.reloadList = reloadList
    }

    // MARK: - Create

    /// Creates a volume from a configuration. Returns whether it succeeded so a sheet can
    /// dismiss only on success.
    @discardableResult
    public func create(_ config: VolumeConfiguration) async -> Bool {
        busy.insert(config.name)
        defer { busy.remove(config.name) }
        do {
            try await backend.createVolume(config)
            await reloadList()
            onActivity("Created volume “\(config.name)”.")
            return true
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
            return false
        }
    }

    /// Validates a draft, then creates. A validation failure sets `notice` and returns false
    /// without touching the backend; on success it routes through `create(_ config:)`. This is
    /// the entry point the create sheet calls, keeping the UI free of `VolumeConfiguration`.
    @discardableResult
    public func create(draft: VolumeDraft) async -> Bool {
        switch validatedConfiguration(draft) {
        case let .success(config):
            return await create(config)
        case let .failure(error):
            notice = LifecycleNotice(detail: error.detail)
            return false
        }
    }

    // MARK: - Delete

    public func delete(name: String) async {
        await deleteAll(names: [name])
    }

    /// Deletes one or more volumes in a single `volume delete` call (there is no `--force`;
    /// the runtime refuses an in-use volume and we surface that error).
    public func deleteAll(names: [String]) async {
        guard !names.isEmpty else { return }
        names.forEach { busy.insert($0) }
        defer { names.forEach { busy.remove($0) } }
        do {
            try await backend.deleteVolumes(names: names)
            await reloadList()
            onActivity(
                names.count == 1
                    ? "Deleted volume “\(names[0])”." : "Deleted \(names.count) volumes.")
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
        }
    }

    // MARK: - Prune

    /// The volumes a prune would remove: those with zero attachments (best-effort, computed
    /// from the attachment index). The runtime owns the authoritative reference check.
    public func computePruneTargets() async -> [Volume] {
        let summaries = (try? await backend.listVolumes()) ?? []
        let containers = (try? await backend.listContainers(all: true)) ?? []
        let index = AttachmentIndex.build(
            from: containers.map(Container.init(summary:)).map(ContainerAttachmentInfo.init(container:)))
        return summaries
            .map { Volume(summary: $0, attachedContainers: index.containers(forVolume: $0.name)) }
            .filter { $0.attachedContainers.isEmpty }
    }

    @discardableResult
    public func prune() async -> PruneSummary {
        do {
            let result = try await backend.pruneVolumes()
            await reloadList()
            let message = result.reclaimedDescription ?? "Cleanup complete."
            onActivity(message)
            return PruneSummary(message: message)
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
            return PruneSummary(message: "Cleanup failed.")
        }
    }

    // MARK: - Validation

    /// Validates a draft into a `VolumeConfiguration`, or returns the first field error.
    public func validatedConfiguration(_ draft: VolumeDraft) -> Result<VolumeConfiguration, CapsuleError>
    {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return .failure(.invalidInput(field: "name", message: "Enter a volume name."))
        }
        let size = draft.size.trimmingCharacters(in: .whitespacesAndNewlines)
        if !size.isEmpty, !VolumeDraft.isValidSize(size) {
            return .failure(
                .invalidInput(
                    field: "size",
                    message: "Size must be a number with a K/M/G/T/P suffix, e.g. 10G."))
        }
        let config = VolumeConfiguration(
            name: name,
            size: size.isEmpty ? nil : size,
            options: draft.options.compactMap(\.token),
            labels: draft.labels.compactMap(\.token))
        return .success(config)
    }

    // MARK: - Domain-primitive accessors (consumed by CreateVolumeSheet)

    /// The `container …` command the current draft would run, or the bare `container volume
    /// create` shell while the draft is still invalid. Returns a plain String so the sheet
    /// never names `VolumeConfiguration` or touches `.arguments`.
    public func commandPreview(for draft: VolumeDraft) -> String {
        switch validatedConfiguration(draft) {
        case let .success(config):
            return (["container"] + config.arguments).joined(separator: " ")
        case .failure:
            return "container volume create"
        }
    }

    /// nil when the draft is valid; otherwise the human-readable reason (for inline display).
    public func validationMessage(_ draft: VolumeDraft) -> String? {
        switch validatedConfiguration(draft) {
        case .success:
            return nil
        case let .failure(error):
            return error.detail.explanation
        }
    }

    /// Whether the draft validates — drives the Create button's enabled state.
    public func isValid(_ draft: VolumeDraft) -> Bool {
        if case .success = validatedConfiguration(draft) { return true }
        return false
    }
}
```

- [ ] **Step 4: Run it, expect PASS.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter VolumeActionsModelTests` → all pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/CapsuleDomain/VolumeActionsModel.swift Tests/CapsuleUnitTests/VolumeActionsModelTests.swift
git commit -m "feat(volumes): VolumeActionsModel (create/delete/prune, draft validation, preview accessors)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 3.5: Volume confirmation kinds + builders (additive)

**Files:**
- Modify: `Sources/CapsuleDomain/Confirmation.swift` (insert two cases into `ConfirmationKind`; append two static builders to the `ConfirmationRequest` extension — both edits are **additive**, never replacing the whole enum or struct body)
- Modify: `Tests/CapsuleUnitTests/ConfirmationTests.swift` (append new tests before the closing brace)

**Interfaces:**
- Consumes (Phase 2): `AttachmentIndex`, `AttachmentIndex(volumes:networks:)`, `AttachmentIndex.containers(forVolume:) -> [String]`.
- Consumes (existing): `ConfirmationRequest(title:message:confirmTitle:targetIDs:kind:)`.
- Produces: `ConfirmationKind.deleteVolume`, `ConfirmationKind.pruneVolumes`; `ConfirmationRequest.deleteVolume(names:attachments:) -> ConfirmationRequest?`; `ConfirmationRequest.pruneVolumes() -> ConfirmationRequest`.

**Steps:**

- [ ] **Step 1: Write the failing tests** — append to `Tests/CapsuleUnitTests/ConfirmationTests.swift` immediately before the final closing brace (after the existing image tests):

```swift
    // MARK: - Volumes (M8)

    func testDeleteVolumeWarnsDataLossAndCarriesKind() {
        let request = ConfirmationRequest.deleteVolume(
            names: ["data"], attachments: AttachmentIndex(volumes: [:], networks: [:]))
        XCTAssertEqual(request?.kind, .deleteVolume)
        XCTAssertEqual(request?.targetIDs, ["data"])
        XCTAssertEqual(
            request?.message, "Deleting data permanently destroys its data.",
            "an unattached volume warns about data loss only")
    }

    func testDeleteVolumeIncludesMountingContainers() {
        let index = AttachmentIndex(volumes: ["data": ["web", "db"]], networks: [:])
        let request = ConfirmationRequest.deleteVolume(names: ["data"], attachments: index)
        let message = request?.message ?? ""
        XCTAssertTrue(message.contains("permanently destroys its data."))
        XCTAssertTrue(message.contains("It is mounted by:"))
        XCTAssertTrue(message.contains("web"))
        XCTAssertTrue(message.contains("db"))
        XCTAssertTrue(message.contains("delete will fail until they are removed"))
    }

    func testDeleteVolumeNilForEmptySelection() {
        XCTAssertNil(
            ConfirmationRequest.deleteVolume(
                names: [], attachments: AttachmentIndex(volumes: [:], networks: [:])))
    }

    func testPruneVolumesConfirmation() {
        let request = ConfirmationRequest.pruneVolumes()
        XCTAssertEqual(request.kind, .pruneVolumes)
        XCTAssertTrue(request.message.localizedCaseInsensitiveContains("destroy"))
    }
```

- [ ] **Step 2: Run it, expect a compile FAIL.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ConfirmationTests` → `error: type 'ConfirmationKind' has no member 'deleteVolume'`.

- [ ] **Step 3a: ADD the two enum cases (additive insertion — do NOT rewrite the enum).** In `Sources/CapsuleDomain/Confirmation.swift`, locate the existing `ConfirmationKind` enum and insert the two volume cases immediately **after** the existing `case deleteImage` line, leaving every existing case untouched. The result reads:

```swift
    // Images (Milestone 6)
    case deleteImage
    // Volumes (Milestone 8) — NO force variant (the CLI has no --force).
    case deleteVolume
    case pruneVolumes
```

> Insert only the three lines `// Volumes (Milestone 8) …`, `case deleteVolume`, `case pruneVolumes`. The Phase-4 network cases (`deleteNetwork`/`pruneNetworks`) will be inserted beside these by that phase.

- [ ] **Step 3b: APPEND the two builders (additive insertion — do NOT rewrite the extension).** In `Sources/CapsuleDomain/Confirmation.swift`, inside the existing `extension ConfirmationRequest`, insert the following block immediately **after** the existing `deleteImage(ids:)` builder and **before** the extension's closing brace:

```swift
    // MARK: Volumes (Milestone 8)

    /// Deleting a volume always confirms — it permanently destroys data. When the volume is
    /// still mounted, the message names the mounting containers and warns the delete will
    /// fail until they are removed (there is no force-delete).
    public static func deleteVolume(
        names: [String], attachments: AttachmentIndex
    ) -> ConfirmationRequest? {
        guard !names.isEmpty else { return nil }
        let mounters = Array(Set(names.flatMap { attachments.containers(forVolume: $0) })).sorted()
        let subject =
            names.count == 1
            ? "Deleting \(names[0]) permanently destroys its data."
            : "Deleting \(names.count) volumes permanently destroys their data."
        var message = subject
        if !mounters.isEmpty {
            message +=
                " It is mounted by: \(mounters.joined(separator: ", ")); "
                + "delete will fail until they are removed."
        }
        return ConfirmationRequest(
            title: names.count == 1 ? "Delete volume?" : "Delete \(names.count) volumes?",
            message: message,
            confirmTitle: "Delete",
            targetIDs: names, kind: .deleteVolume)
    }

    /// Cleaning up volumes removes every volume with no container references and destroys
    /// their data — always confirm.
    public static func pruneVolumes() -> ConfirmationRequest {
        ConfirmationRequest(
            title: "Clean Up Volumes?",
            message: "This removes all volumes with no container references. Data in those "
                + "volumes is permanently destroyed.",
            confirmTitle: "Clean Up",
            targetIDs: [], kind: .pruneVolumes)
    }
```

- [ ] **Step 4: Run it, expect PASS.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ConfirmationTests` → all pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/CapsuleDomain/Confirmation.swift Tests/CapsuleUnitTests/ConfirmationTests.swift
git commit -m "feat(volumes): deleteVolume/pruneVolumes confirmation kinds + builders

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 3.6: `CreateVolumeSheet` (Domain-primitive only — advanced disclosure + command preview)

**Files:**
- Create: `Sources/CapsuleUI/CreateVolumeSheet.swift`

**Interfaces:**
- Consumes (Task 3.2): `VolumeDraft`, `KeyValueRow`.
- Consumes (Task 3.4): `VolumeActionsModel.commandPreview(for:) -> String`, `.validationMessage(_:) -> String?`, `.isValid(_:) -> Bool`, `.create(draft:) async -> Bool`.
- Consumes (existing UI): `CapsuleColors.activitySurface`.
- Produces: `struct CreateVolumeSheet: View`.
- **Arch-guard:** imports ONLY `CapsuleDomain` + `SwiftUI`. It MUST NOT name `VolumeConfiguration` or call `.arguments`/`validatedConfiguration` — the preview String and validity come from the model, exactly as `QuickRunSheet`/`BuildSheet` read `model.commandPreview`.
- Verification: this is a SwiftUI view (no unit test in this repo's convention) — verified by `make build` + `make check`.

**Steps:**

- [ ] **Step 1: Write the view** at `Sources/CapsuleUI/CreateVolumeSheet.swift`:

```swift
//
//  CreateVolumeSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Create Volume sheet: a required Name field, an "Advanced Options" disclosure (size,
//  driver --opt rows, label rows), and a live `container volume create …` command preview.
//  Low-risk, so there is no confirmation; Create is disabled until the draft validates.
//
//  This view imports only CapsuleDomain + SwiftUI and consumes only Domain primitives: the
//  command-preview String, the validity accessors, and the draft-taking create on
//  VolumeActionsModel. It never names a backend Configuration type — mirroring how QuickRunSheet
//  and BuildSheet are backed by RunModel/BuildModel.

import CapsuleDomain
import SwiftUI

struct CreateVolumeSheet: View {
    let actions: VolumeActionsModel
    var onClose: () -> Void

    @State private var draft = VolumeDraft()
    @State private var showAdvanced = false
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Create Volume", systemImage: "externaldrive.badge.plus")
                .font(.headline)

            labeledField("Name (required)", text: $draft.name, prompt: "data")

            DisclosureGroup("Advanced Options", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    labeledField("Size", text: $draft.size, prompt: "10G")
                    keyValueEditor(
                        "Driver options (--opt)", rows: $draft.options,
                        keyPrompt: "journaling", valuePrompt: "on")
                    keyValueEditor(
                        "Labels (--label)", rows: $draft.labels,
                        keyPrompt: "env", valuePrompt: "dev")
                }
                .padding(.top, 6)
            }

            commandPreview

            if !draft.name.isEmpty, let message = actions.validationMessage(draft) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Cancel", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isCreating || !actions.isValid(draft))
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var commandPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Command preview").font(.caption).foregroundStyle(.secondary)
            Text(actions.commandPreview(for: draft))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(CapsuleColors.activitySurface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func create() {
        isCreating = true
        Task {
            let ok = await actions.create(draft: draft)
            isCreating = false
            if ok { onClose() }
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
        }
    }

    private func keyValueEditor(
        _ label: String, rows: Binding<[KeyValueRow]>, keyPrompt: String, valuePrompt: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    rows.wrappedValue.append(KeyValueRow())
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help("Add a row")
            }
            ForEach(rows.wrappedValue.indices, id: \.self) { index in
                HStack {
                    TextField(keyPrompt, text: rows[index].key)
                        .textFieldStyle(.roundedBorder)
                    Text("=").foregroundStyle(.secondary)
                    TextField(valuePrompt, text: rows[index].value)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        rows.wrappedValue.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify it builds and passes static checks.** `make build && make check`. Expected: build succeeds; lint/arch/headers clean (in particular the arch guard confirms `CapsuleUI` imports no backend module and this file names no `VolumeConfiguration`).

- [ ] **Step 3: Commit.**

```bash
git add Sources/CapsuleUI/CreateVolumeSheet.swift
git commit -m "feat(volumes): CreateVolumeSheet (Domain-primitive preview + advanced disclosure)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 3.7: `VolumePruneSheet` (best-effort preview)

**Files:**
- Create: `Sources/CapsuleUI/VolumePruneSheet.swift`

**Interfaces:**
- Consumes (Task 3.4): `VolumeActionsModel.computePruneTargets() -> [Volume]`, `VolumeActionsModel.prune() -> PruneSummary`.
- Consumes (Task 3.1): `Volume`.
- Produces: `struct VolumePruneSheet: View`.
- **Arch-guard:** imports ONLY `CapsuleDomain` + `SwiftUI`.
- Verification: SwiftUI view — verified by `make build` + `make check`.

**Steps:**

- [ ] **Step 1: Write the view** at `Sources/CapsuleUI/VolumePruneSheet.swift`:

```swift
//
//  VolumePruneSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The volume Clean Up sheet: a best-effort preview of the zero-attachment volumes a prune
//  would remove, then the actual reclaimed result after running. The runtime owns the
//  authoritative reference check, so the preview is labelled best-effort.

import CapsuleDomain
import SwiftUI

struct VolumePruneSheet: View {
    let actions: VolumeActionsModel
    let onClose: () -> Void

    @State private var targets: [Volume] = []
    @State private var isLoading = true
    @State private var isPruning = false
    @State private var resultMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Clean Up Volumes", systemImage: "trash")
                .font(.headline)

            if let resultMessage {
                Text(resultMessage).font(.callout)
            } else if isLoading {
                ProgressView("Finding unused volumes…")
            } else if targets.isEmpty {
                Text("No unused volumes to remove.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(targets.count) volume(s) will be removed:")
                    .font(.callout)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(targets) { volume in
                            Text("• \(volume.name)")
                                .font(.system(.callout, design: .monospaced))
                        }
                    }
                }
                .frame(maxHeight: 160)
                Text(
                    "This preview is best-effort; the runtime decides the final set. The "
                        + "actual reclaimed result is shown after cleanup."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button(resultMessage == nil ? "Cancel" : "Done", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if resultMessage == nil {
                    Button("Clean Up", role: .destructive) {
                        Task {
                            isPruning = true
                            let summary = await actions.prune()
                            resultMessage = summary.message
                            isPruning = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || isPruning)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { await reloadTargets() }
    }

    private func reloadTargets() async {
        isLoading = true
        targets = await actions.computePruneTargets()
        isLoading = false
    }
}
```

- [ ] **Step 2: Verify it builds and passes static checks.** `make build && make check`.

- [ ] **Step 3: Commit.**

```bash
git add Sources/CapsuleUI/VolumePruneSheet.swift
git commit -m "feat(volumes): VolumePruneSheet best-effort preview + result

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 3.8: `VolumeInspectorView` (Summary + Raw JSON)

**Files:**
- Create: `Sources/CapsuleUI/VolumeInspectorView.swift`

**Interfaces:**
- Consumes (Task 3.3): `VolumeBrowserModel.selection`, `.selectedVolumes`, `.inspect(name:) -> VolumeInspection`.
- Consumes (Task 3.1): `Volume` (`name`, `source`, `sizeBytes`, `createdAt`, `attachedContainers`, `options`, `labels`).
- Consumes (existing UI): `Pasteboard.copy`, `JSONPrettyPrinter.prettyPrint`.
- Produces: `struct VolumeInspectorView: View`.
- Verification: SwiftUI view — verified by `make build` + `make check`.

**Steps:**

- [ ] **Step 1: Write the view** at `Sources/CapsuleUI/VolumeInspectorView.swift`:

```swift
//
//  VolumeInspectorView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The volumes inspector: a Summary tab (name, source, size, created, and the prominent
//  attached-containers list) plus a Raw JSON tab fed by `volume inspect`. The raw payload is
//  always shown even when decoding drifts, and is copyable. AppKit (NSPasteboard) is
//  permitted in the UI layer.

import AppKit
import CapsuleDomain
import SwiftUI

struct VolumeInspectorView: View {
    let model: VolumeBrowserModel

    @State private var rawJSON = ""
    @State private var isLoadingRaw = false

    init(model: VolumeBrowserModel) {
        self.model = model
    }

    /// The single selected volume, when exactly one row is selected.
    private var solo: Volume? {
        guard model.selection.count == 1, let id = model.selection.first else { return nil }
        return model.selectedVolumes.first { $0.id == id }
    }

    var body: some View {
        TabView {
            summaryTab
                .tabItem { Label("Summary", systemImage: "info.circle") }
            rawTab
                .tabItem { Label("Raw JSON", systemImage: "curlybraces") }
        }
        .task(id: model.selection) { await loadRaw() }
    }

    // MARK: Summary

    @ViewBuilder
    private var summaryTab: some View {
        if model.selection.isEmpty {
            ContentUnavailableView(
                "No Selection", systemImage: "externaldrive",
                description: Text("Select a volume to see its details."))
        } else if let volume = solo {
            Form {
                Section("Volume") {
                    LabeledContent("Name", value: volume.name)
                    LabeledContent("Source", value: volume.source ?? "—")
                    LabeledContent("Size") {
                        if let bytes = volume.sizeBytes {
                            Text(bytes, format: .byteCount(style: .file))
                        } else {
                            Text("—")
                        }
                    }
                    if let created = volume.createdAt {
                        LabeledContent("Created") { Text(created, format: .dateTime) }
                    }
                }

                Section("Attached containers (\(volume.attachedContainers.count))") {
                    if volume.attachedContainers.isEmpty {
                        Text("Not mounted by any container.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(volume.attachedContainers, id: \.self) { name in
                            Text(name)
                        }
                    }
                }

                if !volume.options.isEmpty {
                    Section("Driver options") {
                        ForEach(volume.options.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                            LabeledContent(pair.key, value: pair.value)
                        }
                    }
                }

                if !volume.labels.isEmpty {
                    Section("Labels") {
                        ForEach(volume.labels.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                            LabeledContent(pair.key, value: pair.value)
                        }
                    }
                }

                Section {
                    Button {
                        Pasteboard.copy(volume.name)
                    } label: {
                        Label("Copy Name", systemImage: "doc.on.doc")
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "\(model.selection.count) Volumes Selected",
                systemImage: "externaldrive",
                description: Text("Select a single volume to see its details."))
        }
    }

    // MARK: Raw JSON

    @ViewBuilder
    private var rawTab: some View {
        if solo == nil {
            ContentUnavailableView(
                "No Selection", systemImage: "curlybraces",
                description: Text("Select a single volume to inspect its raw JSON."))
        } else {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        Pasteboard.copy(rawJSON)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .disabled(rawJSON.isEmpty)
                }
                .padding(8)

                Divider()

                ScrollView([.vertical, .horizontal]) {
                    Text(rawJSON.isEmpty ? "No raw payload available." : rawJSON)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .overlay {
                    if isLoadingRaw { ProgressView() }
                }
            }
        }
    }

    // MARK: Actions

    private func loadRaw() async {
        guard let volume = solo else {
            rawJSON = ""
            return
        }
        isLoadingRaw = true
        let inspection = await model.inspect(name: volume.id)
        rawJSON = JSONPrettyPrinter.prettyPrint(inspection.rawJSON)
        isLoadingRaw = false
    }
}
```

- [ ] **Step 2: Verify it builds and passes static checks.** `make build && make check`.

- [ ] **Step 3: Commit.**

```bash
git add Sources/CapsuleUI/VolumeInspectorView.swift
git commit -m "feat(volumes): VolumeInspectorView (Summary + Raw JSON, attached containers)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 3.9: `VolumeListView` (Table + context menu + toolbar)

**Files:**
- Create: `Sources/CapsuleUI/VolumeListView.swift`

**Interfaces:**
- Consumes (Task 3.3): `VolumeBrowserModel` (`rows`, `selection`, `searchText`, `loadState`, `isEmptyButHealthy`, `noMatches`, `allVolumes`, `refresh()`).
- Consumes (Task 3.4): `VolumeActionsModel.deleteAll(names:)`, `.prune()`.
- Consumes (Task 3.5): `ConfirmationRequest.deleteVolume(names:attachments:)`, `.kind == .deleteVolume`.
- Consumes (Phase 2): `AttachmentIndex(volumes:networks:)`.
- Consumes (Tasks 3.6/3.7, existing UI): `CreateVolumeSheet`, `VolumePruneSheet`, `ConfirmationSheet`.
- Produces: `struct VolumeListView: View` with `init(model:actions:)`, `enum VolumeSheet: Identifiable`. Consumed by `ContentColumnView` in Task 3.10.
- **No gating:** the view exposes Create/Clean Up unconditionally (capability gating is Phase 6's, applied at the `ContentColumnView` arm).
- Verification: SwiftUI view — verified by `make build` + `make check`.

> Note on attachment-aware delete: the delete confirmation embeds mounting-container names. The list rebuilds an `AttachmentIndex` from `model.allVolumes` (each row already carries `attachedContainers`, stamped on refresh) so it needs no extra backend call — it maps `name -> attachedContainers` directly.

**Steps:**

- [ ] **Step 1: Write the view** at `Sources/CapsuleUI/VolumeListView.swift`:

```swift
//
//  VolumeListView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The volumes content column: a Table backed by VolumeBrowserModel (read surface) with a
//  context menu (Inspect, Delete…) and a toolbar (Create…, Clean Up, Refresh). Delete
//  confirmations embed the mounting-container warning from the per-row attachment list.

import CapsuleDomain
import SwiftUI

struct VolumeListView: View {
    @Bindable var model: VolumeBrowserModel
    let actions: VolumeActionsModel

    @State private var activeSheet: VolumeSheet?

    init(model: VolumeBrowserModel, actions: VolumeActionsModel) {
        self.model = model
        self.actions = actions
    }

    var body: some View {
        content
            .searchable(text: $model.searchText, prompt: "Search volumes")
            .toolbar { toolbarContent }
            .task { await model.refresh() }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .create:
                    CreateVolumeSheet(actions: actions, onClose: { activeSheet = nil })
                case .prune:
                    VolumePruneSheet(actions: actions, onClose: { activeSheet = nil })
                case let .confirm(request):
                    ConfirmationSheet(
                        request: request,
                        onConfirm: { req in
                            activeSheet = nil
                            performConfirmed(req)
                        }, onCancel: { activeSheet = nil })
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading:
            ProgressView("Loading volumes…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let detail):
            ContentUnavailableView {
                Label(detail.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(detail.explanation)
            }
        case .loaded:
            if model.isEmptyButHealthy {
                ContentUnavailableView {
                    Label("No volumes yet", systemImage: "externaldrive")
                } description: {
                    Text("Volumes you create will appear here.")
                }
            } else {
                table
            }
        }
    }

    private var table: some View {
        Table(model.rows, selection: $model.selection) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("Size") { volume in
                if let bytes = volume.sizeBytes {
                    Text(bytes, format: .byteCount(style: .file)).foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            TableColumn("Attached") { volume in
                if volume.attachedContainers.isEmpty {
                    Text("—").foregroundStyle(.secondary)
                } else {
                    Text("\(volume.attachedContainers.count)")
                        .help(volume.attachedContainers.joined(separator: ", "))
                }
            }
            TableColumn("Created") { volume in
                if let created = volume.createdAt {
                    Text(created, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu(forSelectionType: Volume.ID.self) { ids in
            rowMenu(for: ids)
        }
        .onDeleteCommand { requestDelete(ids: model.selection) }
        .overlay {
            if model.noMatches { ContentUnavailableView.search }
        }
    }

    @ViewBuilder
    private func rowMenu(for ids: Set<Volume.ID>) -> some View {
        let targets = volumes(for: ids)
        if let single = targets.first, targets.count == 1 {
            Button("Inspect") { model.selection = [single.id] }
            Divider()
        }
        Button("Delete…", role: .destructive) { requestDelete(ids: ids) }
            .disabled(targets.isEmpty)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                activeSheet = .create
            } label: {
                Label("Create", systemImage: "plus")
            }
            .help("Create a volume")

            Button {
                activeSheet = .prune
            } label: {
                Label("Clean Up", systemImage: "trash")
            }
            .help("Remove unused volumes")

            Button {
                Task { await model.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Reload the volume list")
        }
    }

    // MARK: - Destructive actions

    /// Deleting a volume always confirms; the confirmation embeds the data-loss warning and,
    /// when mounted, the mounting-container names.
    private func requestDelete(ids: Set<Volume.ID>) {
        let targets = volumes(for: ids)
        guard !targets.isEmpty else { return }
        if let request = ConfirmationRequest.deleteVolume(
            names: targets.map(\.id), attachments: attachmentIndex())
        {
            activeSheet = .confirm(request)
        }
    }

    private func performConfirmed(_ request: ConfirmationRequest) {
        switch request.kind {
        case .deleteVolume:
            Task { await actions.deleteAll(names: request.targetIDs) }
        default:
            break  // other kinds are not raised by the volumes surface
        }
    }

    /// Rebuilds the attachment index from the already-stamped rows (no extra backend call).
    private func attachmentIndex() -> AttachmentIndex {
        var volumes: [String: [String]] = [:]
        for volume in model.allVolumes where !volume.attachedContainers.isEmpty {
            volumes[volume.name] = volume.attachedContainers
        }
        return AttachmentIndex(volumes: volumes, networks: [:])
    }

    private func volumes(for ids: Set<Volume.ID>) -> [Volume] {
        model.allVolumes.filter { ids.contains($0.id) }
    }
}

/// Which volume sheet is presented.
enum VolumeSheet: Identifiable {
    case create
    case prune
    case confirm(ConfirmationRequest)

    var id: String {
        switch self {
        case .create: return "create"
        case .prune: return "prune"
        case let .confirm(request): return "confirm-\(request.id)"
        }
    }
}
```

- [ ] **Step 2: Verify it builds and passes static checks.** `make build && make check`.

- [ ] **Step 3: Commit.**

```bash
git add Sources/CapsuleUI/VolumeListView.swift
git commit -m "feat(volumes): VolumeListView (Table, context menu, toolbar)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 3.10: Wire volume models through the app (routing + inspector + notice, all additive)

**Files:**
- Modify: `Sources/CapsuleApp/AppEnvironment.swift` (struct props; `init` params/assignments; `live()` body — **additive insertions** beside the image models)
- Modify: `Sources/CapsuleApp/CapsuleScene.swift` (`@State` props; `init(environment:)`; `RootView(...)` call — **additive**)
- Modify: `Sources/CapsuleUI/RootView.swift` (private lets; `init`; `AppShellView(...)` call — **additive**)
- Modify: `Sources/CapsuleUI/AppShellView.swift` (props; `init`; `ContentColumnView(...)` call; inspector switch arm; `volumeActionsModel.notice` overlay — **additive**)
- Modify: `Sources/CapsuleUI/ContentColumnView.swift` (props; `runningContent` switch arm — **additive**)
- Modify: `Tests/CapsuleUnitTests/CompositionTests.swift` (append a test before the closing brace)

**Interfaces:**
- Consumes (Tasks 3.3/3.4): `VolumeBrowserModel(backend:normalize:onActivity:)`, `VolumeActionsModel(backend:normalize:onActivity:reloadList:)`.
- Consumes (Tasks 3.8/3.9): `VolumeInspectorView(model:)`, `VolumeListView(model:actions:)`.
- Consumes (existing): `ErrorNormalizer.normalize`, `shell.appendActivity`, `LifecycleNoticeView`.
- Produces: `AppEnvironment.volumeBrowserModel`, `AppEnvironment.volumeActionsModel`, the `.volumes` content + inspector routes, and the rendered `volumeActionsModel.notice` overlay.
- **No gating:** the `.volumes` content arm routes unconditionally; Phase 6 later wraps it with capability gating.

**Steps:**

- [ ] **Step 1: Write the failing composition test** — append to `Tests/CapsuleUnitTests/CompositionTests.swift` before the final closing brace:

```swift
    @MainActor
    func testLiveEnvironmentExposesVolumeModels() {
        let environment = AppEnvironment.live()

        XCTAssertEqual(environment.volumeBrowserModel.loadState, .idle)
        XCTAssertTrue(environment.volumeBrowserModel.allVolumes.isEmpty)
        XCTAssertTrue(environment.volumeActionsModel.busy.isEmpty)
        XCTAssertNil(environment.volumeActionsModel.notice)
    }
```

- [ ] **Step 2: Run it, expect a compile FAIL.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CompositionTests` → `error: value of type 'AppEnvironment' has no member 'volumeBrowserModel'`.

- [ ] **Step 3a: ADD the models to `AppEnvironment` (struct + init).** In `Sources/CapsuleApp/AppEnvironment.swift`, insert the two stored properties immediately **after** the existing `public var imageActionsModel: ImageActionsModel` line:

```swift
    public var imageActionsModel: ImageActionsModel
    public var volumeBrowserModel: VolumeBrowserModel
    public var volumeActionsModel: VolumeActionsModel
```

Insert the matching `init` parameters immediately **after** the existing `imageActionsModel: ImageActionsModel,` parameter:

```swift
        imageActionsModel: ImageActionsModel,
        volumeBrowserModel: VolumeBrowserModel,
        volumeActionsModel: VolumeActionsModel,
```

Insert the matching assignments immediately **after** the existing `self.imageActionsModel = imageActionsModel` line:

```swift
        self.imageActionsModel = imageActionsModel
        self.volumeBrowserModel = volumeBrowserModel
        self.volumeActionsModel = volumeActionsModel
```

- [ ] **Step 3b: Construct them in `live()`.** In `Sources/CapsuleApp/AppEnvironment.swift`, immediately **after** the existing `let imageActionsModel = ImageActionsModel(...)` block, insert:

```swift
        let volumeBrowserModel = VolumeBrowserModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) }
        )
        let volumeActionsModel = VolumeActionsModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            reloadList: { await volumeBrowserModel.refresh() }
        )
```

Pass them into the `AppEnvironment(...)` returned at the end of `live()`, immediately **after** the existing `imageActionsModel: imageActionsModel,` argument:

```swift
            imageActionsModel: imageActionsModel,
            volumeBrowserModel: volumeBrowserModel,
            volumeActionsModel: volumeActionsModel,
```

- [ ] **Step 3c: Thread through `CapsuleScene`.** In `Sources/CapsuleApp/CapsuleScene.swift`, insert the `@State` properties immediately **after** the existing `imageActionsModel` `@State`:

```swift
    @State private var imageActionsModel: ImageActionsModel
    @State private var volumeBrowserModel: VolumeBrowserModel
    @State private var volumeActionsModel: VolumeActionsModel
```

Insert the `init(environment:)` assignments immediately **after** the existing `imageActionsModel` assignment:

```swift
        self._imageActionsModel = State(initialValue: environment.imageActionsModel)
        self._volumeBrowserModel = State(initialValue: environment.volumeBrowserModel)
        self._volumeActionsModel = State(initialValue: environment.volumeActionsModel)
```

Pass them into the `RootView(...)` call immediately **after** the existing `imageActionsModel: imageActionsModel,` argument:

```swift
                imageActionsModel: imageActionsModel,
                volumeBrowserModel: volumeBrowserModel,
                volumeActionsModel: volumeActionsModel,
```

- [ ] **Step 3d: Thread through `RootView`.** In `Sources/CapsuleUI/RootView.swift`, insert private lets immediately **after** the existing `imageActionsModel` let:

```swift
    private let imageActionsModel: ImageActionsModel
    private let volumeBrowserModel: VolumeBrowserModel
    private let volumeActionsModel: VolumeActionsModel
```

Insert `init` parameters immediately **after** the existing `imageActionsModel: ImageActionsModel,` parameter:

```swift
        imageActionsModel: ImageActionsModel,
        volumeBrowserModel: VolumeBrowserModel,
        volumeActionsModel: VolumeActionsModel,
```

Insert assignments immediately **after** the existing `self.imageActionsModel = imageActionsModel` line:

```swift
        self.imageActionsModel = imageActionsModel
        self.volumeBrowserModel = volumeBrowserModel
        self.volumeActionsModel = volumeActionsModel
```

Pass them into the `AppShellView(...)` call immediately **after** the existing `imageActionsModel: imageActionsModel,` argument:

```swift
            imageActionsModel: imageActionsModel,
            volumeBrowserModel: volumeBrowserModel,
            volumeActionsModel: volumeActionsModel,
```

- [ ] **Step 3e: Thread through `AppShellView` + add the inspector arm.** In `Sources/CapsuleUI/AppShellView.swift`, insert properties immediately **after** the existing `imageActionsModel` property:

```swift
    @Bindable var imageActionsModel: ImageActionsModel
    @Bindable var volumeBrowserModel: VolumeBrowserModel
    let volumeActionsModel: VolumeActionsModel
```

Insert `init` parameters immediately **after** the existing `imageActionsModel: ImageActionsModel,` parameter:

```swift
        imageActionsModel: ImageActionsModel,
        volumeBrowserModel: VolumeBrowserModel,
        volumeActionsModel: VolumeActionsModel,
```

Insert assignments immediately **after** the existing `self.imageActionsModel = imageActionsModel` line:

```swift
        self.imageActionsModel = imageActionsModel
        self.volumeBrowserModel = volumeBrowserModel
        self.volumeActionsModel = volumeActionsModel
```

Pass them into the `ContentColumnView(...)` call immediately **after** the existing `imageActionsModel: imageActionsModel,` argument:

```swift
                imageActionsModel: imageActionsModel,
                volumeBrowserModel: volumeBrowserModel,
                volumeActionsModel: volumeActionsModel,
```

Insert the `.volumes` inspector arm immediately **after** the existing `case .images:` arm in the `.inspector` switch (leaving the trailing `default:` in place):

```swift
                case .images:
                    ImageInspectorView(model: imageBrowserModel)
                case .volumes:
                    VolumeInspectorView(model: volumeBrowserModel)
                default:
                    InspectorView(section: shell.selection)
```

- [ ] **Step 3f: RENDER the `volumeActionsModel.notice` overlay (additive).** In `Sources/CapsuleUI/AppShellView.swift`, locate the existing overlay that renders `imageActionsModel.notice` (a `LifecycleNoticeView` whose dismiss sets `imageActionsModel.notice = nil`) and insert a sibling overlay immediately **after** it, mirroring it for volumes:

```swift
        // existing — leave in place:
        .overlay(alignment: .bottom) {
            if let notice = imageActionsModel.notice {
                LifecycleNoticeView(notice: notice) { imageActionsModel.notice = nil }
            }
        }
        // M8 — add beside it:
        .overlay(alignment: .bottom) {
            if let notice = volumeActionsModel.notice {
                LifecycleNoticeView(notice: notice) { volumeActionsModel.notice = nil }
            }
        }
```

- [ ] **Step 3g: Route the content arm in `ContentColumnView` (no gating).** In `Sources/CapsuleUI/ContentColumnView.swift`, insert the two model properties immediately **after** the existing `imageActionsModel` property:

```swift
    let imageActionsModel: ImageActionsModel
    let volumeBrowserModel: VolumeBrowserModel
    let volumeActionsModel: VolumeActionsModel
```

Insert the `.volumes` arm in `runningContent` immediately **after** the existing `case .images:` arm (leaving the trailing `default:` in place). Route unconditionally — no `health.availableFeatures` check (Phase 6 owns in-pane gating):

```swift
        case .images:
            ImageListView(
                model: imageBrowserModel, actions: imageActionsModel, runModel: runModel,
                buildModel: buildModel)
        case .volumes:
            VolumeListView(model: volumeBrowserModel, actions: volumeActionsModel)
        default:
            resourcePlaceholder
```

- [ ] **Step 4: Run the focused test + full build/check.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CompositionTests` → passes. Then `make build && make check` → clean. The `.volumes` route is now live; the sidebar's existing `.volumes` row already gates *selectability* on `SystemFeature.volumes` (pre-existing), and Phase 6 will add the in-pane capability gating around this arm.

- [ ] **Step 5: Run the whole suite to confirm no regression.** `make test` → green.

- [ ] **Step 6: Commit.**

```bash
git add Sources/CapsuleApp/AppEnvironment.swift Sources/CapsuleApp/CapsuleScene.swift Sources/CapsuleUI/RootView.swift Sources/CapsuleUI/AppShellView.swift Sources/CapsuleUI/ContentColumnView.swift Tests/CapsuleUnitTests/CompositionTests.swift
git commit -m "feat(volumes): wire VolumeBrowserModel/VolumeActionsModel into shell + inspector

Routes .volumes to VolumeListView/VolumeInspectorView, renders the volumeActionsModel
notice overlay, and threads the models through AppEnvironment → CapsuleScene → RootView →
AppShellView → ContentColumnView. All edits are additive; capability gating is Phase 6's.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---


---

## Phase 4: Networks surface (domain + UI)

This phase delivers the complete Networks surface: the domain `Network` model (with `isBuiltin`), pure subnet-conflict validation (`NetworkValidation` over the Phase-2 `CIDR`), `NetworkBrowserModel` (whose `refresh()` stamps `connectedContainers` via the Phase-2 `AttachmentIndex`), `NetworkActionsModel` (synchronous create/delete/prune + draft validation + the Create-sheet validity accessors), the `.deleteNetwork`/`.pruneNetworks` confirmation kinds with builtin protection, and the full UI (`NetworkListView`, `NetworkInspectorView`, `CreateNetworkSheet`, `NetworkPruneSheet`) wired into `ContentColumnView`/`AppShellView`/`RootView`/`AppEnvironment`/`CapsuleScene`.

It consumes Phase 1's `NetworkSummary` (extended), `NetworkConfiguration`, backend methods (`listNetworks`/`inspectNetwork`/`createNetwork`/`deleteNetworks`/`pruneNetworks`), `ContainerSummary.networkNames`/`Container.networkNames`; Phase 2's `CIDR` + `AttachmentIndex`/`ContainerAttachmentInfo`; and Phase 3's `KeyValueRow`. It produces `Network`, `NetworkValidation`, `NetworkDraft`, `NetworkBrowserModel`/`NetworkInspection`/`NetworkLoadState`, `NetworkActionsModel` (incl. `commandPreview(for:)`, `subnetConflictMessage(for:against:)`, `canCreate(_:against:)`, `create(draft:against:)`), the `.deleteNetwork`/`.pruneNetworks` confirmation kinds + builders, and the four UI views + `NetworkSheet`. It is the sibling of Phase 3 (Volumes); Phase 6 close-out exercises it in the live GUI smoke and owns ALL capability gating.

> **Binding-rule compliance baked in here:**
> - `CreateNetworkSheet` imports only `CapsuleDomain` + `SwiftUI`, never names `NetworkConfiguration`, never calls `.arguments`, and never calls `NetworkValidation` directly — it reads `commandPreview(for:)` + `subnetConflictMessage(for:against:)` + `canCreate(_:against:)` from `NetworkActionsModel` and submits via `create(draft:against:)`. This mirrors M7's `RunModel`/`BuildModel` + `QuickRunSheet`/`BuildSheet`.
> - `networkActionsModel.notice` is rendered in `AppShellView` (mirroring the `imageActionsModel.notice` block).
> - All edits to shared/App-layer files (`Confirmation.swift`, `ContentColumnView`, `AppShellView`, `RootView`, `CapsuleScene`, `AppEnvironment`, `CompositionTests`) are **additive** and assume Phase 3's volume additions are already present. No whole-enum / whole-switch / whole-struct replacements.
> - **No capability-gating logic is added here** — Phase 6 owns `SystemHealth.supports`, the sidebar, the `ContentColumnView` family arms, and the DNS pane. This phase wires only the `.networks` routing + inspector arms.

---

### Task 4.1: Network domain model

**Files:**
- Create `Sources/CapsuleDomain/Network.swift`
- Create `Tests/CapsuleUnitTests/NetworkTests.swift`

**Interfaces:**
- Consumes (Phase 1, `CapsuleBackend`): `NetworkSummary(id:name:mode:gateway:subnet:plugin:ipv6Subnet:labels:createdAt:isBuiltin:)` with fields `id, name, mode?, gateway?, subnet?, plugin?, ipv6Subnet?, labels:[String:String], createdAt?, isBuiltin`.
- Consumes (existing): `Container.parseDate(_:)` (static, tolerant ISO-8601).
- Produces: `Network` (`Sendable, Equatable, Identifiable`) with `id, name, mode?, plugin?, ipv4Subnet?, ipv4Gateway?, ipv6Subnet?, internal:Bool, labels:[String:String], createdAt:Date?, connectedContainers:[String], isBuiltin:Bool`; `init(summary:connectedContainers:)`.

**Steps:**

- [ ] **Step 1: Write the failing test.** Create `Tests/CapsuleUnitTests/NetworkTests.swift`:

```swift
//
//  NetworkTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The domain Network model: mapping a backend NetworkSummary into a UI-friendly value,
//  including the builtin flag and the derived connected-container stamp.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

final class NetworkTests: XCTestCase {
    func testInitFromSummaryMapsEveryField() {
        let summary = NetworkSummary(
            id: "default", name: "default", mode: "nat", gateway: "192.168.64.1",
            subnet: "192.168.64.0/24", plugin: "container-network-vmnet",
            ipv6Subnet: "fdb6:5eb:8ee:85cf::/64",
            labels: ["com.apple.container.resource.role": "builtin"],
            createdAt: "2026-06-27T12:15:24Z", isBuiltin: true)

        let network = Network(summary: summary, connectedContainers: ["web"])

        XCTAssertEqual(network.id, "default")
        XCTAssertEqual(network.name, "default")
        XCTAssertEqual(network.mode, "nat")
        XCTAssertEqual(network.plugin, "container-network-vmnet")
        XCTAssertEqual(network.ipv4Subnet, "192.168.64.0/24")
        XCTAssertEqual(network.ipv4Gateway, "192.168.64.1")
        XCTAssertEqual(network.ipv6Subnet, "fdb6:5eb:8ee:85cf::/64")
        XCTAssertTrue(network.isBuiltin)
        XCTAssertEqual(network.connectedContainers, ["web"])
        XCTAssertNotNil(network.createdAt)
        XCTAssertFalse(network.internal, "summary carries no internal flag; defaults to false")
    }

    func testConnectedContainersDefaultEmpty() {
        let network = Network(summary: NetworkSummary(id: "br0", name: "br0"))
        XCTAssertEqual(network.connectedContainers, [])
        XCTAssertFalse(network.isBuiltin)
    }
}
```

- [ ] **Step 2: Run it — expect a build failure.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NetworkTests` → fails to compile with `error: cannot find type 'Network' in scope` (and `cannot find 'Network' in scope`).

- [ ] **Step 3: Write the implementation.** Create `Sources/CapsuleDomain/Network.swift`:

```swift
//
//  Network.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The domain's
//  model of a container network — decoupled from the backend wire format. Subnet/gateway
//  are surfaced as copyable IPAM detail; `connectedContainers` is derived from the
//  attachment cross-reference; `isBuiltin` marks the runtime's protected networks.

import CapsuleBackend
import Foundation

/// The domain's model of a container network.
public struct Network: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var mode: String?
    public var plugin: String?
    public var ipv4Subnet: String?
    public var ipv4Gateway: String?
    public var ipv6Subnet: String?
    public var `internal`: Bool
    public var labels: [String: String]
    public var createdAt: Date?
    /// Containers attached to this network, derived from `container list -a`'s
    /// `configuration.networks[].network`. Empty until stamped by the browser model.
    public var connectedContainers: [String]
    /// A runtime-owned network (labelled `com.apple.container.resource.role: builtin`, e.g.
    /// `default`). Protected: cannot be deleted, excluded from prune/bulk.
    public var isBuiltin: Bool

    public init(
        id: String, name: String, mode: String? = nil, plugin: String? = nil,
        ipv4Subnet: String? = nil, ipv4Gateway: String? = nil, ipv6Subnet: String? = nil,
        internal: Bool = false, labels: [String: String] = [:], createdAt: Date? = nil,
        connectedContainers: [String] = [], isBuiltin: Bool = false
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.plugin = plugin
        self.ipv4Subnet = ipv4Subnet
        self.ipv4Gateway = ipv4Gateway
        self.ipv6Subnet = ipv6Subnet
        self.`internal` = `internal`
        self.labels = labels
        self.createdAt = createdAt
        self.connectedContainers = connectedContainers
        self.isBuiltin = isBuiltin
    }
}

extension Network {
    /// Maps a backend summary into the domain model, parsing the creation date and carrying
    /// the derived attachment stamp. `internal` is not exposed by `network list`, so it
    /// defaults to false (it is only ever set when creating a network).
    public init(summary: NetworkSummary, connectedContainers: [String] = []) {
        self.init(
            id: summary.id,
            name: summary.name,
            mode: summary.mode,
            plugin: summary.plugin,
            ipv4Subnet: summary.subnet,
            ipv4Gateway: summary.gateway,
            ipv6Subnet: summary.ipv6Subnet,
            internal: false,
            labels: summary.labels,
            createdAt: summary.createdAt.flatMap(Container.parseDate),
            connectedContainers: connectedContainers,
            isBuiltin: summary.isBuiltin)
    }
}
```

- [ ] **Step 4: Run it — expect PASS.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NetworkTests` → 2 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/CapsuleDomain/Network.swift Tests/CapsuleUnitTests/NetworkTests.swift
git commit -m "feat(networks): domain Network model with isBuiltin + connectedContainers

Maps the extended NetworkSummary (plugin/ipv6/labels/builtin) into a UI-friendly
domain value; connectedContainers is the attachment stamp filled by the browser.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 4.2: NetworkValidation — subnet-conflict check (pure)

**Files:**
- Create `Sources/CapsuleDomain/NetworkValidation.swift`
- Create `Tests/CapsuleUnitTests/NetworkValidationTests.swift`

**Interfaces:**
- Consumes (Phase 2, `CapsuleDomain`): `CIDR.parse(_ text: String) -> CIDR.Parsed?`, `CIDR.overlaps(_ lhs: String, _ rhs: String) -> Bool` (false if families differ or either malformed).
- Consumes (Task 4.1): `Network` (`ipv4Subnet?`, `ipv6Subnet?`, `name`).
- Produces: `enum NetworkValidation { static func subnetConflict(subnet: String, against existingNetworks: [Network]) -> String? }` — `nil` = no conflict / empty subnet; non-nil naming the conflicting network or a syntax hint for malformed CIDR. **Consumed only by `NetworkActionsModel`** (the Create sheet reaches it through the model's validity accessor, never directly).

**Steps:**

- [ ] **Step 1: Write the failing test.** Create `Tests/CapsuleUnitTests/NetworkValidationTests.swift`:

```swift
//
//  NetworkValidationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The pure subnet-conflict check: empty is allowed (CLI auto-assigns), malformed yields a
//  syntax hint, and an overlap names the conflicting network and both subnets.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

final class NetworkValidationTests: XCTestCase {
    private func net(_ name: String, v4: String? = nil, v6: String? = nil) -> Network {
        Network(summary: NetworkSummary(id: name, name: name, subnet: v4, ipv6Subnet: v6))
    }

    func testEmptyOrBlankSubnetIsAllowed() {
        XCTAssertNil(NetworkValidation.subnetConflict(subnet: "", against: []))
        XCTAssertNil(NetworkValidation.subnetConflict(subnet: "   ", against: []))
    }

    func testMalformedSubnetYieldsSyntaxHint() {
        let message = NetworkValidation.subnetConflict(subnet: "not-a-cidr", against: [])
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("/") ?? false, "the hint shows an example CIDR")
    }

    func testOverlapNamesTheConflictingNetworkAndBothSubnets() {
        let existing = [net("default", v4: "192.168.64.0/24")]
        let message = NetworkValidation.subnetConflict(
            subnet: "192.168.64.128/25", against: existing)
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("default") ?? false)
        XCTAssertTrue(message?.contains("192.168.64.0/24") ?? false, "names the existing subnet")
        XCTAssertTrue(message?.contains("192.168.64.128/25") ?? false, "echoes the attempt")
    }

    func testNonOverlappingSubnetIsClear() {
        let existing = [net("default", v4: "192.168.64.0/24")]
        XCTAssertNil(NetworkValidation.subnetConflict(subnet: "10.0.0.0/24", against: existing))
    }

    func testIPv4SubnetDoesNotConflictWithIPv6Existing() {
        let existing = [net("v6net", v6: "fd00::/32")]
        XCTAssertNil(
            NetworkValidation.subnetConflict(subnet: "10.0.0.0/24", against: existing),
            "different families never overlap")
    }

    func testIPv6OverlapIsDetected() {
        let existing = [net("v6net", v6: "fd00::/32")]
        let message = NetworkValidation.subnetConflict(subnet: "fd00:0:0:1::/64", against: existing)
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("v6net") ?? false)
    }
}
```

- [ ] **Step 2: Run it — expect a build failure.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NetworkValidationTests` → `error: cannot find 'NetworkValidation' in scope`.

- [ ] **Step 3: Write the implementation.** Create `Sources/CapsuleDomain/NetworkValidation.swift`:

```swift
//
//  NetworkValidation.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The pure subnet-
//  conflict check behind the Create Network sheet's live validation. We detect and report
//  overlaps (naming the conflicting network) but never auto-pick a free subnet. The UI never
//  calls this directly — NetworkActionsModel surfaces it via subnetConflictMessage.

import Foundation

public enum NetworkValidation {
    /// Returns `nil` when `subnet` is empty (the runtime auto-assigns) or conflict-free.
    /// A malformed CIDR yields a syntax hint with an example; an overlap yields a message
    /// naming the conflicting network and both subnets so the user can resolve it.
    public static func subnetConflict(
        subnet: String, against existingNetworks: [Network]
    ) -> String? {
        let trimmed = subnet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard CIDR.parse(trimmed) != nil else {
            return "“\(trimmed)” isn’t a valid CIDR subnet (for example, 10.0.0.0/24)."
        }
        for network in existingNetworks {
            for existing in [network.ipv4Subnet, network.ipv6Subnet].compactMap({ $0 }) {
                if CIDR.overlaps(trimmed, existing) {
                    return "Subnet \(trimmed) overlaps with network “\(network.name)” "
                        + "(\(existing))."
                }
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run it — expect PASS.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NetworkValidationTests` → 6 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/CapsuleDomain/NetworkValidation.swift Tests/CapsuleUnitTests/NetworkValidationTests.swift
git commit -m "feat(networks): pure subnet-conflict validation over CIDR

Detects+reports IPv4/IPv6 subnet overlaps naming the conflicting network; empty is
allowed (CLI auto-assigns), malformed yields a syntax hint. No auto-pick (YAGNI).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 4.3: NetworkDraft

**Files:**
- Create `Sources/CapsuleDomain/NetworkDraft.swift`
- Create `Tests/CapsuleUnitTests/NetworkDraftTests.swift`

**Interfaces:**
- Consumes (Phase 3, `CapsuleDomain`): `KeyValueRow` (`id:UUID, key:String, value:String`, `init(id:key:value:)` all defaulted, `var token: String? { key.isEmpty ? nil : "\(key)=\(value)" }`).
- Produces: `NetworkDraft` (`Sendable, Equatable`) with `name, subnet, subnetV6: String`, `isInternal: Bool`, `options, labels: [KeyValueRow]`, `plugin: String`; all-defaulted `init`.

**Steps:**

- [ ] **Step 1: Write the failing test.** Create `Tests/CapsuleUnitTests/NetworkDraftTests.swift`:

```swift
//
//  NetworkDraftTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Create Network sheet's editable draft: raw UI strings + key/value rows that the
//  actions model validates into a NetworkConfiguration.

import XCTest

@testable import CapsuleDomain

final class NetworkDraftTests: XCTestCase {
    func testDefaultsAreEmptyAndNotInternal() {
        let draft = NetworkDraft()
        XCTAssertTrue(draft.name.isEmpty)
        XCTAssertTrue(draft.subnet.isEmpty)
        XCTAssertTrue(draft.subnetV6.isEmpty)
        XCTAssertFalse(draft.isInternal)
        XCTAssertTrue(draft.options.isEmpty)
        XCTAssertTrue(draft.labels.isEmpty)
        XCTAssertTrue(draft.plugin.isEmpty)
    }

    func testRowsCarryKeyValueTokens() {
        let draft = NetworkDraft(
            name: "app-net",
            options: [KeyValueRow(key: "mtu", value: "1400")],
            labels: [KeyValueRow(key: "team", value: "infra"), KeyValueRow()])
        XCTAssertEqual(draft.options.compactMap(\.token), ["mtu=1400"])
        XCTAssertEqual(draft.labels.compactMap(\.token), ["team=infra"], "blank rows drop out")
    }
}
```

- [ ] **Step 2: Run it — expect a build failure.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NetworkDraftTests` → `error: cannot find type 'NetworkDraft' in scope`.

- [ ] **Step 3: Write the implementation.** Create `Sources/CapsuleDomain/NetworkDraft.swift`:

```swift
//
//  NetworkDraft.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The editable draft
//  behind the Create Network sheet. `NetworkActionsModel.validatedConfiguration` turns it
//  into a backend `NetworkConfiguration` (the argv single-source-of-truth) after the
//  subnet-conflict check.

import Foundation

public struct NetworkDraft: Sendable, Equatable {
    public var name: String
    public var subnet: String
    public var subnetV6: String
    public var isInternal: Bool
    public var options: [KeyValueRow]
    public var labels: [KeyValueRow]
    public var plugin: String

    public init(
        name: String = "",
        subnet: String = "",
        subnetV6: String = "",
        isInternal: Bool = false,
        options: [KeyValueRow] = [],
        labels: [KeyValueRow] = [],
        plugin: String = ""
    ) {
        self.name = name
        self.subnet = subnet
        self.subnetV6 = subnetV6
        self.isInternal = isInternal
        self.options = options
        self.labels = labels
        self.plugin = plugin
    }
}
```

- [ ] **Step 4: Run it — expect PASS.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NetworkDraftTests` → 2 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/CapsuleDomain/NetworkDraft.swift Tests/CapsuleUnitTests/NetworkDraftTests.swift
git commit -m "feat(networks): NetworkDraft for the Create Network sheet

Raw UI fields + reusable KeyValueRow option/label rows; validated into a
NetworkConfiguration by NetworkActionsModel.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 4.4: Network confirmation kinds + builders (builtin protection)

**Files:**
- Modify `Sources/CapsuleDomain/Confirmation.swift` (additive only — insert two enum cases + a new Networks builder section)
- Modify `Tests/CapsuleUnitTests/ConfirmationTests.swift` (append a Networks section)

**Interfaces:**
- Consumes (Phase 2, `CapsuleDomain`): `AttachmentIndex(volumes:networks:)`, `AttachmentIndex.containers(forNetwork: String) -> [String]`.
- Produces: `ConfirmationKind.deleteNetwork`, `ConfirmationKind.pruneNetworks`; `ConfirmationRequest.deleteNetwork(name:isBuiltin:attachments:) -> ConfirmationRequest?` (nil for builtin), `ConfirmationRequest.pruneNetworks() -> ConfirmationRequest`.

> **ADDITIVE — Phase 3 ran first.** By the time this task executes, Phase 3 has already added `.deleteVolume`/`.pruneVolumes` to `ConfirmationKind` and the `// MARK: Volumes (Milestone 8)` builders to `ConfirmationRequest`. Every edit below INSERTS new lines/sections; it never rewrites the `ConfirmationKind` enum body, the `ConfirmationRequest` struct/extension body, or any closing brace.

**Steps:**

- [ ] **Step 1: Write the failing tests.** Append to `Tests/CapsuleUnitTests/ConfirmationTests.swift`, immediately after Phase 3's `// MARK: - Volumes (M8)` section and before the file's final closing `}` (do not modify Phase 3's appended tests):

```swift
    // MARK: - Networks (M8)

    func testDeleteNetworkReturnsNilForBuiltin() {
        let index = AttachmentIndex(volumes: [:], networks: [:])
        XCTAssertNil(
            ConfirmationRequest.deleteNetwork(
                name: "default", isBuiltin: true, attachments: index),
            "builtin networks are protected — no confirmation, Delete disabled in the UI")
    }

    func testDeleteNetworkConfirmsAndNamesConnectedContainers() {
        let index = AttachmentIndex(volumes: [:], networks: ["app-net": ["web", "db"]])
        let request = ConfirmationRequest.deleteNetwork(
            name: "app-net", isBuiltin: false, attachments: index)
        XCTAssertEqual(request?.kind, .deleteNetwork)
        XCTAssertEqual(request?.targetIDs, ["app-net"])
        XCTAssertTrue(request?.message.contains("app-net") ?? false)
        XCTAssertTrue(request?.message.contains("web") ?? false, "connected containers are named")
    }

    func testDeleteNetworkWithoutConnectionsOmitsTheList() {
        let index = AttachmentIndex(volumes: [:], networks: [:])
        let request = ConfirmationRequest.deleteNetwork(
            name: "idle", isBuiltin: false, attachments: index)
        XCTAssertNotNil(request)
        XCTAssertFalse(request?.message.contains("Connected containers") ?? true)
    }

    func testPruneNetworksConfirmation() {
        let request = ConfirmationRequest.pruneNetworks()
        XCTAssertEqual(request.kind, .pruneNetworks)
        XCTAssertTrue(request.targetIDs.isEmpty)
    }
```

- [ ] **Step 2: Run it — expect a build failure.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ConfirmationTests` → `error: type 'ConfirmationKind' has no member 'deleteNetwork'`.

- [ ] **Step 3: Add the enum cases (additive).** In `Sources/CapsuleDomain/Confirmation.swift`, the `ConfirmationKind` enum already carries Phase 3's M8 region (the `// M8 …` comment plus `case deleteVolume` and `case pruneVolumes`). Insert two new cases by anchoring on Phase 3's cases — **do not** rewrite the enum or its closing brace:

  - Replace the single line `    case deleteVolume` with:
    ```swift
        case deleteVolume
        case deleteNetwork
    ```
  - Replace the single line `    case pruneVolumes` with:
    ```swift
        case pruneVolumes
        case pruneNetworks
    ```

  The resulting M8 region matches Contract §4.14:
  ```swift
      // M8 — NO force variants (no --force exists):
      case deleteVolume
      case deleteNetwork
      case pruneVolumes
      case pruneNetworks
  ```

- [ ] **Step 4: Add the builders (additive).** In the same file, Phase 3 added a `// MARK: Volumes (Milestone 8)` section of static builders on `ConfirmationRequest`, the last of which is `pruneVolumes()`. Locate the closing `}` of that `pruneVolumes()` function and INSERT a brand-new `// MARK: Networks (Milestone 8)` section immediately after it (still inside the same `ConfirmationRequest` scope, before that scope's closing brace). Insert only the new section; do not touch Phase 3's builders, the `deleteImage` builder, or any closing brace:

```swift
    // MARK: Networks (Milestone 8)

    /// Deleting a network always confirms; a builtin (e.g. `default`) is protected and
    /// returns no request so the UI disables Delete. The message names any connected
    /// containers — there is no `--force`, so delete fails while they remain attached.
    public static func deleteNetwork(
        name: String, isBuiltin: Bool, attachments: AttachmentIndex
    ) -> ConfirmationRequest? {
        guard !isBuiltin else { return nil }
        let connected = attachments.containers(forNetwork: name)
        var message = "Delete network \(name)?"
        if !connected.isEmpty {
            message += " Connected containers: \(connected.joined(separator: ", "))."
        }
        return ConfirmationRequest(
            title: "Delete network?", message: message,
            confirmTitle: "Delete", targetIDs: [name], kind: .deleteNetwork)
    }

    /// Clean Up removes every network with no connections; builtin networks are never
    /// touched. Always confirms (multi-item, data-affecting).
    public static func pruneNetworks() -> ConfirmationRequest {
        ConfirmationRequest(
            title: "Clean Up Networks?",
            message: "This removes every network with no connected containers. "
                + "Builtin networks are never removed.",
            confirmTitle: "Clean Up", targetIDs: [], kind: .pruneNetworks)
    }
```

> If Phase 3 happened to place its volume builders inside a dedicated `extension ConfirmationRequest { … }`, insert this Networks section in that same extension (after `pruneVolumes()`); the anchor is "after Phase 3's `pruneVolumes()` builder", not the file's last brace.

- [ ] **Step 5: Run it — expect PASS.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ConfirmationTests` → all tests pass (existing + Phase 3's + the 4 new networks tests).

- [ ] **Step 6: Commit.**

```bash
git add Sources/CapsuleDomain/Confirmation.swift Tests/CapsuleUnitTests/ConfirmationTests.swift
git commit -m "feat(networks): deleteNetwork/pruneNetworks confirmations with builtin protection

Builtin networks return no confirmation request (Delete disabled in UI); the delete
message names connected containers from the attachment index. No force variants.
Additive over Phase 3's volume cases/builders — no whole-enum/struct rewrite.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 4.5: NetworkBrowserModel (read surface + attachment stamping)

**Files:**
- Create `Sources/CapsuleDomain/NetworkBrowserModel.swift`
- Create `Tests/CapsuleUnitTests/NetworkBrowserModelTests.swift`

**Interfaces:**
- Consumes (Phase 1, `CapsuleBackend`): `ContainerBackend.listNetworks() -> [NetworkSummary]`, `inspectNetwork(names:) -> Parsed<[NetworkSummary]>`, `listContainers(all:) -> [ContainerSummary]`; `MockBackend(networks:containers:)`; `ContainerSummary(... networkNames:)`.
- Consumes (Phase 2, `CapsuleDomain`): `AttachmentIndex.build(from:)`, `containers(forNetwork:)`; `ContainerAttachmentInfo(container:)`.
- Consumes (Task 4.1): `Network`, `init(summary:connectedContainers:)`. Consumes (existing): `Container(summary:)`, `SystemStatusModel.defaultNormalize`.
- Produces: `enum NetworkLoadState { idle, loading, loaded, unavailable(ErrorDetail) }`; `struct NetworkInspection { value: Network?; rawJSON: String; init(value:rawJSON:) }`; `@MainActor @Observable final class NetworkBrowserModel` with `allNetworks`, `loadState`, `searchText`, `selection`, `rows`, `selectedNetworks`, `isEmptyButHealthy`, `noMatches`, `init(backend:normalize:onActivity:)`, `refresh()`, `inspect(name:)`.

**Steps:**

- [ ] **Step 1: Write the failing test.** Create `Tests/CapsuleUnitTests/NetworkBrowserModelTests.swift`:

```swift
//
//  NetworkBrowserModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The networks read surface: loading (down service vs genuinely empty), search, selection,
//  raw-retaining inspect, and the connected-container stamp built from the attachment index.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class NetworkBrowserModelTests: XCTestCase {
    func testRefreshLoadsAndStampsConnectedContainers() async {
        let backend = MockBackend(
            containers: [
                ContainerSummary(
                    id: "c1", name: "web", image: "alpine:latest", state: "running",
                    networkNames: ["default"])
            ],
            networks: [
                NetworkSummary(id: "default", name: "default", isBuiltin: true),
                NetworkSummary(id: "br0", name: "br0"),
            ])
        let model = NetworkBrowserModel(backend: backend)

        await model.refresh()

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.allNetworks.count, 2)
        XCTAssertEqual(
            model.allNetworks.first { $0.name == "default" }?.connectedContainers, ["web"])
        XCTAssertEqual(model.allNetworks.first { $0.name == "br0" }?.connectedContainers, [])
    }

    func testUnavailableIsDistinctFromEmpty() async {
        let backend = MockBackend(networks: [])
        backend.failure = BackendError.nonZeroExit(
            command: "container network list", code: 1, stderr: "Connection refused")
        let model = NetworkBrowserModel(backend: backend)

        await model.refresh()

        guard case .unavailable = model.loadState else {
            return XCTFail("a daemon failure must surface as .unavailable, not an empty list")
        }
        XCTAssertFalse(model.isEmptyButHealthy)
    }

    func testEmptyButHealthyWhenServiceUpButNoNetworks() async {
        let model = NetworkBrowserModel(backend: MockBackend(networks: []))
        await model.refresh()
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertTrue(model.isEmptyButHealthy)
    }

    func testSearchMatchesNameAndSubnet() async {
        let backend = MockBackend(networks: [
            NetworkSummary(id: "default", name: "default", subnet: "192.168.64.0/24"),
            NetworkSummary(id: "br0", name: "br0", subnet: "10.0.0.0/24"),
        ])
        let model = NetworkBrowserModel(backend: backend)
        await model.refresh()

        model.searchText = "br0"
        XCTAssertEqual(model.rows.map(\.name), ["br0"])

        model.searchText = "192.168"
        XCTAssertEqual(model.rows.map(\.name), ["default"], "subnet is searchable")
    }

    func testSelectionIsIntersectedOnRefresh() async {
        let backend = MockBackend(networks: [NetworkSummary(id: "default", name: "default")])
        let model = NetworkBrowserModel(backend: backend)
        await model.refresh()
        model.selection = ["default", "ghost"]

        await model.refresh()

        XCTAssertEqual(model.selection, ["default"], "stale ids are dropped")
    }

    func testInspectReturnsDecodedValue() async {
        let backend = MockBackend(networks: [NetworkSummary(id: "default", name: "default")])
        let model = NetworkBrowserModel(backend: backend)
        let inspection = await model.inspect(name: "default")
        XCTAssertEqual(inspection.value?.name, "default")
    }
}
```

- [ ] **Step 2: Run it — expect a build failure.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NetworkBrowserModelTests` → `error: cannot find 'NetworkBrowserModel' in scope`.

- [ ] **Step 3: Write the implementation.** Create `Sources/CapsuleDomain/NetworkBrowserModel.swift`:

```swift
//
//  NetworkBrowserModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The networks read
//  surface, mirroring `ImageBrowserModel`: a loaded list with a live query, a multi-
//  selection, and raw-retaining inspect. On refresh it also reads `container list -a`,
//  builds an `AttachmentIndex`, and stamps each network's `connectedContainers`. Network
//  mutations (create/delete/prune) live in `NetworkActionsModel`.

import CapsuleBackend
import Foundation
import Observation

/// The load state of the network list, kept separate from `rows` so the UI can distinguish
/// "service unreachable" from "no networks" from "no matches".
public enum NetworkLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case unavailable(ErrorDetail)
}

/// A network inspection: the decoded domain value (nil if the payload drifted) paired with
/// the exact raw JSON, so the inspector can always show *something*.
public struct NetworkInspection: Sendable, Equatable {
    public var value: Network?
    public var rawJSON: String

    public init(value: Network?, rawJSON: String) {
        self.value = value
        self.rawJSON = rawJSON
    }
}

@MainActor
@Observable
public final class NetworkBrowserModel {
    public private(set) var allNetworks: [Network] = []
    public private(set) var loadState: NetworkLoadState = .idle

    public var searchText: String = ""
    public var selection: Set<Network.ID> = []

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

    /// Networks passing the search term, ordered by name.
    public var rows: [Network] {
        allNetworks
            .filter { matchesSearch($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public var selectedNetworks: [Network] {
        allNetworks.filter { selection.contains($0.id) }
    }

    /// The service is up but there are genuinely no networks (distinct from a down service
    /// and from a search that matched nothing).
    public var isEmptyButHealthy: Bool {
        loadState == .loaded && allNetworks.isEmpty
    }

    /// There are networks, but the active search matched none.
    public var noMatches: Bool {
        loadState == .loaded && !allNetworks.isEmpty && rows.isEmpty
    }

    private func matchesSearch(_ network: Network) -> Bool {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        return network.name.localizedCaseInsensitiveContains(term)
            || (network.ipv4Subnet?.localizedCaseInsensitiveContains(term) ?? false)
            || (network.ipv6Subnet?.localizedCaseInsensitiveContains(term) ?? false)
            || (network.mode?.localizedCaseInsensitiveContains(term) ?? false)
    }

    // MARK: Loading

    public func refresh() async {
        loadState = .loading
        do {
            let summaries = try await backend.listNetworks()
            let attachments = await loadAttachmentIndex()
            allNetworks = summaries.map { summary in
                Network(
                    summary: summary,
                    connectedContainers: attachments.containers(forNetwork: summary.name))
            }
            selection = selection.intersection(Set(allNetworks.map(\.id)))
            loadState = .loaded
            onActivity("Loaded \(allNetworks.count) network(s).")
        } catch {
            allNetworks = []
            let detail = normalize(error).detail
            onActivity("Failed to load networks: \(detail.title)")
            loadState = .unavailable(detail)
        }
    }

    /// Inspects one network, mapping the backend's raw-retaining `Parsed` into the domain
    /// `NetworkInspection`. Never throws: a failure yields an empty raw payload.
    public func inspect(name: String) async -> NetworkInspection {
        do {
            let parsed = try await backend.inspectNetwork(names: [name])
            let summary = parsed.value?.first
            return NetworkInspection(
                value: summary.map { Network(summary: $0) },
                rawJSON: parsed.raw)
        } catch {
            return NetworkInspection(value: nil, rawJSON: "")
        }
    }

    // MARK: Attachment cross-reference

    /// Best-effort read of `container list -a` → an attachment index. A failure (e.g. the
    /// service is mid-recovery) degrades to an empty index rather than failing the list.
    private func loadAttachmentIndex() async -> AttachmentIndex {
        let containers = ((try? await backend.listContainers(all: true)) ?? [])
            .map(Container.init(summary:))
        return AttachmentIndex.build(from: containers.map(ContainerAttachmentInfo.init(container:)))
    }
}
```

- [ ] **Step 4: Run it — expect PASS.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NetworkBrowserModelTests` → 6 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/CapsuleDomain/NetworkBrowserModel.swift Tests/CapsuleUnitTests/NetworkBrowserModelTests.swift
git commit -m "feat(networks): NetworkBrowserModel (list/search/inspect + attachment stamp)

Mirrors ImageBrowserModel; refresh() reads container list -a, builds an AttachmentIndex,
and stamps each network's connectedContainers. Down service stays distinct from empty.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 4.6: NetworkActionsModel (create/delete/prune + validation + Create-sheet validity accessors)

**Files:**
- Create `Sources/CapsuleDomain/NetworkActionsModel.swift`
- Create `Tests/CapsuleUnitTests/NetworkActionsModelTests.swift`

**Interfaces:**
- Consumes (Phase 1, `CapsuleBackend`): `ContainerBackend.createNetwork(_ config: NetworkConfiguration)`, `deleteNetworks(names:)`, `pruneNetworks() -> PruneResult`, `listNetworks()`, `listContainers(all:)`; `NetworkConfiguration(name:subnet:subnetV6:internal:options:labels:plugin:)` with computed `arguments`; `PruneResult.reclaimedDescription`.
- Consumes (Phase 2): `AttachmentIndex.build(from:)`/`containers(forNetwork:)`, `ContainerAttachmentInfo(container:)`.
- Consumes (Tasks 4.1/4.2/4.3): `Network`, `NetworkValidation.subnetConflict(subnet:against:)`, `NetworkDraft`; (existing) `LifecycleNotice`, `PruneSummary`, `CapsuleError.invalidInput`, `ConfirmationRequest`, `SystemStatusModel.defaultNormalize`.
- Produces: `@MainActor @Observable final class NetworkActionsModel` with `busy: Set<String>`, `notice: LifecycleNotice?`, `confirmation: ConfirmationRequest?`, `init(backend:normalize:onActivity:reloadList:)`, `create(_:) -> Bool`, `delete(name:)`, `deleteAll(names:)`, `prune() -> PruneSummary`, `computePruneTargets() -> [Network]`, `validatedConfiguration(_:against:) -> Result<NetworkConfiguration, CapsuleError>`, plus the **Create-sheet-facing** helpers that keep `NetworkConfiguration`/`NetworkValidation` out of the UI: `commandPreview(for:) -> String`, `subnetConflictMessage(for:against:) -> String?`, `canCreate(_:against:) -> Bool`, and `create(draft:against:) -> Bool`.

**Steps:**

- [ ] **Step 1: Write the failing test.** Create `Tests/CapsuleUnitTests/NetworkActionsModelTests.swift`:

```swift
//
//  NetworkActionsModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The synchronous network operations: draft validation (required name + subnet-conflict),
//  the Create-sheet validity accessors (commandPreview/subnetConflictMessage/canCreate),
//  create/delete/prune success+failure surfacing, and the builtin-excluding prune preview.

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class NetworkActionsModelTests: XCTestCase {
    private func model(_ backend: MockBackend, reload: @escaping () -> Void = {})
        -> NetworkActionsModel
    {
        NetworkActionsModel(backend: backend, reloadList: { reload() })
    }

    // MARK: Validation

    func testValidatedConfigurationBuildsArgvInOrder() {
        let draft = NetworkDraft(
            name: "  app-net  ", subnet: "10.10.0.0/24", subnetV6: "fd00::/64",
            isInternal: true,
            options: [KeyValueRow(key: "mtu", value: "1400")],
            labels: [KeyValueRow(key: "team", value: "infra"), KeyValueRow()],
            plugin: "container-network-vmnet")

        guard case let .success(config) =
            model(MockBackend()).validatedConfiguration(draft, against: [])
        else {
            return XCTFail("a valid draft must produce a configuration")
        }

        XCTAssertEqual(config.name, "app-net", "name is trimmed")
        XCTAssertEqual(
            config.arguments,
            [
                "network", "create", "--internal", "--label", "team=infra",
                "--option", "mtu=1400", "--plugin", "container-network-vmnet",
                "--subnet", "10.10.0.0/24", "--subnet-v6", "fd00::/64", "app-net",
            ])
    }

    func testValidatedConfigurationRejectsEmptyName() {
        let result = model(MockBackend()).validatedConfiguration(
            NetworkDraft(name: "   "), against: [])
        guard case let .failure(.invalidInput(field, _)) = result else {
            return XCTFail("an empty name must fail validation")
        }
        XCTAssertEqual(field, "name")
    }

    func testValidatedConfigurationDetectsSubnetConflict() {
        let existing = [
            Network(summary: NetworkSummary(id: "default", name: "default",
                subnet: "192.168.64.0/24", isBuiltin: true))
        ]
        let result = model(MockBackend()).validatedConfiguration(
            NetworkDraft(name: "dup", subnet: "192.168.64.0/24"), against: existing)
        guard case let .failure(.invalidInput(field, message)) = result else {
            return XCTFail("an overlapping subnet must fail validation")
        }
        XCTAssertEqual(field, "subnet")
        XCTAssertTrue(message.contains("default"), "the conflict names the existing network")
    }

    // MARK: Create-sheet validity accessors

    func testCanCreateRequiresNameAndNoConflict() {
        let existing = [
            Network(summary: NetworkSummary(id: "default", name: "default",
                subnet: "192.168.64.0/24", isBuiltin: true))
        ]
        let m = model(MockBackend())
        XCTAssertFalse(m.canCreate(NetworkDraft(name: "   "), against: existing), "empty name")
        XCTAssertFalse(
            m.canCreate(NetworkDraft(name: "dup", subnet: "192.168.64.0/24"), against: existing),
            "a subnet conflict blocks Create")
        XCTAssertTrue(
            m.canCreate(NetworkDraft(name: "ok", subnet: "10.0.0.0/24"), against: existing))
    }

    func testSubnetConflictMessageNamesExistingNetworkAndAllowsEmpty() {
        let existing = [
            Network(summary: NetworkSummary(id: "default", name: "default",
                subnet: "192.168.64.0/24"))
        ]
        let m = model(MockBackend())
        let message = m.subnetConflictMessage(
            for: NetworkDraft(name: "dup", subnet: "192.168.64.0/24"), against: existing)
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("default") ?? false)
        XCTAssertNil(
            m.subnetConflictMessage(for: NetworkDraft(name: "ok", subnet: ""), against: existing),
            "an empty subnet is allowed (the runtime auto-assigns)")
    }

    // MARK: Create

    func testCreateSucceedsReloadsAndClearsNotice() async {
        var reloads = 0
        let model = model(MockBackend(), reload: { reloads += 1 })

        let ok = await model.create(NetworkConfiguration(name: "br0"))

        XCTAssertTrue(ok)
        XCTAssertEqual(reloads, 1)
        XCTAssertNil(model.notice)
        XCTAssertTrue(model.busy.isEmpty)
    }

    func testCreateFailureSetsNoticeAndReturnsFalse() async {
        let backend = MockBackend()
        backend.failure = BackendError.nonZeroExit(
            command: "container network create", code: 1, stderr: "subnet overlaps existing")
        let model = model(backend)

        let ok = await model.create(NetworkConfiguration(name: "br0"))

        XCTAssertFalse(ok)
        XCTAssertNotNil(model.notice)
    }

    func testCreateFromDraftValidatesThenCreates() async {
        var reloads = 0
        let model = model(MockBackend(), reload: { reloads += 1 })

        let ok = await model.create(draft: NetworkDraft(name: "br0"), against: [])

        XCTAssertTrue(ok)
        XCTAssertEqual(reloads, 1)
    }

    func testCreateFromInvalidDraftSurfacesNoticeWithoutBackendCall() async {
        var reloads = 0
        let model = model(MockBackend(), reload: { reloads += 1 })

        let ok = await model.create(draft: NetworkDraft(name: "   "), against: [])

        XCTAssertFalse(ok)
        XCTAssertNotNil(model.notice, "validation failure surfaces as a notice")
        XCTAssertEqual(reloads, 0, "an invalid draft never reaches the backend")
    }

    func testCommandPreviewReflectsDraft() {
        let preview = model(MockBackend()).commandPreview(
            for: NetworkDraft(name: "br0", subnet: "10.0.0.0/24", isInternal: true))
        XCTAssertTrue(preview.hasPrefix("container network create"))
        XCTAssertTrue(preview.contains("--internal"))
        XCTAssertTrue(preview.contains("--subnet 10.0.0.0/24"))
        XCTAssertTrue(preview.hasSuffix("br0"))
    }

    // MARK: Delete / prune

    func testDeleteReloadsOnSuccess() async {
        var reloads = 0
        let model = model(MockBackend(networks: [NetworkSummary(id: "br0", name: "br0")]),
            reload: { reloads += 1 })

        await model.delete(name: "br0")

        XCTAssertEqual(reloads, 1)
        XCTAssertNil(model.notice)
    }

    func testDeleteFailureSetsNotice() async {
        let backend = MockBackend(networks: [NetworkSummary(id: "br0", name: "br0")])
        backend.failure = BackendError.nonZeroExit(
            command: "container network delete", code: 1, stderr: "network in use")
        let model = model(backend)

        await model.delete(name: "br0")

        XCTAssertNotNil(model.notice)
    }

    func testPruneReturnsSummaryAndReloads() async {
        var reloads = 0
        let model = model(MockBackend(), reload: { reloads += 1 })

        let summary = await model.prune()

        XCTAssertFalse(summary.message.isEmpty)
        XCTAssertEqual(reloads, 1)
    }

    func testComputePruneTargetsExcludesBuiltinAndConnected() async {
        let backend = MockBackend(
            containers: [
                ContainerSummary(
                    id: "c", name: "web", image: "alpine:latest", state: "running",
                    networkNames: ["app-net"])
            ],
            networks: [
                NetworkSummary(id: "default", name: "default", isBuiltin: true),
                NetworkSummary(id: "app-net", name: "app-net"),
                NetworkSummary(id: "idle", name: "idle"),
            ])
        let model = model(backend)

        let targets = await model.computePruneTargets()

        XCTAssertEqual(
            targets.map(\.name), ["idle"],
            "builtin is protected and a connected network is not a prune candidate")
    }
}
```

- [ ] **Step 2: Run it — expect a build failure.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NetworkActionsModelTests` → `error: cannot find 'NetworkActionsModel' in scope`.

- [ ] **Step 3: Write the implementation.** Create `Sources/CapsuleDomain/NetworkActionsModel.swift`:

```swift
//
//  NetworkActionsModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Owns the
//  synchronous (non-streaming, near-instant) network operations — create, delete
//  (single/bulk), and prune — mirroring `ImageActionsModel`'s delete/prune. No Activity
//  tasks (decision §9.1). Draft validation (required name + subnet-conflict) lives here, and
//  the Create sheet reads its validity through commandPreview/subnetConflictMessage/canCreate
//  so it never names the backend `NetworkConfiguration` nor calls `NetworkValidation`.

import CapsuleBackend
import Foundation
import Observation

@MainActor
@Observable
public final class NetworkActionsModel {
    public private(set) var busy: Set<String> = []
    public var notice: LifecycleNotice?
    /// A pending destructive confirmation the UI should present, or nil.
    public var confirmation: ConfirmationRequest?

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void
    private let reloadList: @MainActor () async -> Void

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in },
        reloadList: @escaping @MainActor () async -> Void = {}
    ) {
        self.backend = backend
        self.normalize = normalize
        self.onActivity = onActivity
        self.reloadList = reloadList
    }

    // MARK: - Validation

    /// Validates a draft into a `NetworkConfiguration`. Fails on an empty name and runs the
    /// subnet-conflict check against the currently-known networks (the model never names a
    /// free subnet — it only reports overlaps). Empty subnet is allowed (CLI auto-assigns).
    public func validatedConfiguration(
        _ draft: NetworkDraft, against existingNetworks: [Network]
    ) -> Result<NetworkConfiguration, CapsuleError> {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return .failure(.invalidInput(field: "name", message: "A network name is required."))
        }
        if let conflict = NetworkValidation.subnetConflict(
            subnet: draft.subnet, against: existingNetworks)
        {
            return .failure(.invalidInput(field: "subnet", message: conflict))
        }
        return .success(configuration(from: draft, name: name))
    }

    /// Builds the backend configuration from a draft, trimming optionals to nil. Shared by
    /// `validatedConfiguration` (post-checks) and `commandPreview` (pre-checks).
    private func configuration(from draft: NetworkDraft, name: String) -> NetworkConfiguration {
        let subnet = draft.subnet.trimmingCharacters(in: .whitespacesAndNewlines)
        let subnetV6 = draft.subnetV6.trimmingCharacters(in: .whitespacesAndNewlines)
        let plugin = draft.plugin.trimmingCharacters(in: .whitespacesAndNewlines)
        return NetworkConfiguration(
            name: name,
            subnet: subnet.isEmpty ? nil : subnet,
            subnetV6: subnetV6.isEmpty ? nil : subnetV6,
            internal: draft.isInternal,
            options: draft.options.compactMap(\.token),
            labels: draft.labels.compactMap(\.token),
            plugin: plugin.isEmpty ? nil : plugin)
    }

    // MARK: - Create-sheet validity accessors

    /// The `container network create …` preview for a draft, tolerant of empty required
    /// fields so the sheet can show it live. Keeps `NetworkConfiguration` out of the UI.
    public func commandPreview(for draft: NetworkDraft) -> String {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = configuration(from: draft, name: name)
        return "container " + config.arguments.joined(separator: " ")
    }

    /// The live subnet-conflict message for the Create sheet (nil = clear). Surfaced here so
    /// the sheet sources its inline warning from the model and never calls NetworkValidation.
    public func subnetConflictMessage(
        for draft: NetworkDraft, against existingNetworks: [Network]
    ) -> String? {
        NetworkValidation.subnetConflict(subnet: draft.subnet, against: existingNetworks)
    }

    /// Whether the draft is valid enough to create: a non-empty name and no subnet conflict.
    /// The sheet ANDs this with its own in-flight flag to gate the Create button.
    public func canCreate(_ draft: NetworkDraft, against existingNetworks: [Network]) -> Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && subnetConflictMessage(for: draft, against: existingNetworks) == nil
    }

    // MARK: - Create

    /// Creates a network from an already-validated configuration. Returns whether it
    /// succeeded, so a sheet can dismiss only on success.
    @discardableResult
    public func create(_ config: NetworkConfiguration) async -> Bool {
        busy.insert(config.name)
        defer { busy.remove(config.name) }
        do {
            try await backend.createNetwork(config)
            await reloadList()
            onActivity("Created network “\(config.name)”.")
            return true
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
            return false
        }
    }

    /// UI entry point: validate the draft (surfacing any failure as a notice), then create.
    /// The sheet calls this so it never has to name the backend `NetworkConfiguration`.
    @discardableResult
    public func create(draft: NetworkDraft, against existingNetworks: [Network]) async -> Bool {
        switch validatedConfiguration(draft, against: existingNetworks) {
        case let .success(config):
            return await create(config)
        case let .failure(error):
            notice = LifecycleNotice(detail: error.detail)
            return false
        }
    }

    // MARK: - Delete

    /// Deletes one network. Builtin networks never reach here — the UI disables Delete and
    /// the confirmation builder returns nil for them; the CLI itself also refuses, which we
    /// would surface as a notice.
    public func delete(name: String) async {
        busy.insert(name)
        defer { busy.remove(name) }
        do {
            try await backend.deleteNetworks(names: [name])
            await reloadList()
            onActivity("Deleted network “\(name)”.")
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
        }
    }

    /// Bulk delete (the UI passes only non-builtin names). `network delete` accepts several
    /// names in one call; a batch failure surfaces verbatim as a single notice.
    public func deleteAll(names: [String]) async {
        guard !names.isEmpty else { return }
        names.forEach { busy.insert($0) }
        defer { names.forEach { busy.remove($0) } }
        do {
            try await backend.deleteNetworks(names: names)
            await reloadList()
            onActivity("Deleted \(names.count) network(s).")
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
        }
    }

    // MARK: - Prune

    /// The networks a prune would remove, for the Clean Up sheet's best-effort preview: those
    /// with zero connections, builtins excluded. The runtime owns the authoritative check.
    public func computePruneTargets() async -> [Network] {
        let summaries = (try? await backend.listNetworks()) ?? []
        let containers = ((try? await backend.listContainers(all: true)) ?? [])
            .map(Container.init(summary:))
        let index = AttachmentIndex.build(
            from: containers.map(ContainerAttachmentInfo.init(container:)))
        return summaries
            .map {
                Network(summary: $0, connectedContainers: index.containers(forNetwork: $0.name))
            }
            .filter { !$0.isBuiltin && $0.connectedContainers.isEmpty }
    }

    @discardableResult
    public func prune() async -> PruneSummary {
        do {
            let result = try await backend.pruneNetworks()
            await reloadList()
            let message = result.reclaimedDescription ?? "Cleanup complete."
            onActivity(message)
            return PruneSummary(message: message)
        } catch {
            notice = LifecycleNotice(detail: normalize(error).detail)
            return PruneSummary(message: "Cleanup failed.")
        }
    }
}
```

- [ ] **Step 4: Run it — expect PASS.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NetworkActionsModelTests` → 14 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/CapsuleDomain/NetworkActionsModel.swift Tests/CapsuleUnitTests/NetworkActionsModelTests.swift
git commit -m "feat(networks): NetworkActionsModel (create/delete/prune + draft validation)

Synchronous ops with busy set + LifecycleNotice failure surfacing (no Activity tasks).
validatedConfiguration runs the subnet-conflict check; computePruneTargets excludes
builtins and connected networks. Exposes commandPreview/subnetConflictMessage/canCreate +
create(draft:against:) so the Create sheet sources validity from the model and never
names NetworkConfiguration or calls NetworkValidation.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 4.7: CreateNetworkSheet (UI)

**Files:**
- Create `Sources/CapsuleUI/CreateNetworkSheet.swift`

**Interfaces:**
- Consumes (Tasks 4.3/4.6, `CapsuleDomain`): `NetworkDraft`, `Network`, `KeyValueRow`, and the `NetworkActionsModel` validity surface ONLY — `commandPreview(for:)`, `subnetConflictMessage(for:against:)`, `canCreate(_:against:)`, `create(draft:against:)`; (existing) `CapsuleColors`.
- Produces: `struct CreateNetworkSheet` (used by Task 4.10).

> **Arch guard (CRITICAL):** this sheet imports ONLY `CapsuleDomain` + `SwiftUI`. It MUST NOT import any backend module, MUST NOT name `NetworkConfiguration`, MUST NOT call `.arguments`, and MUST NOT call `NetworkValidation` directly — the live conflict message and the Create-button gate are both sourced from `NetworkActionsModel`. This mirrors M7's `QuickRunSheet`/`BuildSheet` reading `model.commandPreview`.
> **Verification:** UI views have no unit-test harness in this codebase (cf. `ImageListView`/`QuickRunSheet`). The behavioral logic this sheet depends on is fully TDD-covered in Tasks 4.2/4.6. The sheet is verified by `make build` and exercised in the Phase 6 live GUI smoke.

**Steps:**

- [ ] **Step 1: Write the implementation.** Create `Sources/CapsuleUI/CreateNetworkSheet.swift`:

```swift
//
//  CreateNetworkSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Create a network: a required Name and an optional Subnet (with a CIDR hint and live
//  conflict validation), plus an Advanced Options disclosure (IPv6 subnet, Internal toggle,
//  plugin, --option and --label rows). A live command preview shows the exact argv. Low
//  risk, so no confirmation. The sheet never names the backend NetworkConfiguration and never
//  calls the validator directly — it speaks only to NetworkActionsModel (commandPreview,
//  subnetConflictMessage, canCreate, create(draft:against:)).

import CapsuleDomain
import SwiftUI

struct CreateNetworkSheet: View {
    let actions: NetworkActionsModel
    let existingNetworks: [Network]
    let onClose: () -> Void

    @State private var draft = NetworkDraft()
    @State private var busy = false

    /// Live subnet-conflict message (nil = clear), sourced from the model's validity accessor
    /// so the sheet never names NetworkConfiguration nor calls NetworkValidation directly.
    private var subnetConflict: String? {
        actions.subnetConflictMessage(for: draft, against: existingNetworks)
    }

    private var canCreate: Bool {
        actions.canCreate(draft, against: existingNetworks) && !busy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Create Network", systemImage: "network")
                .font(.headline)

            Form {
                TextField("Name", text: $draft.name, prompt: Text("e.g. app-net"))

                VStack(alignment: .leading, spacing: 2) {
                    TextField(
                        "Subnet (optional)", text: $draft.subnet,
                        prompt: Text("e.g. 10.0.0.0/24"))
                    if let conflict = subnetConflict {
                        Text(conflict)
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Leave blank to let the runtime assign a subnet.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                DisclosureGroup("Advanced Options") {
                    TextField("IPv6 subnet", text: $draft.subnetV6, prompt: Text("e.g. fd00::/64"))
                    Toggle("Internal (no external connectivity)", isOn: $draft.isInternal)
                    TextField(
                        "Plugin", text: $draft.plugin,
                        prompt: Text("container-network-vmnet"))
                    keyValueEditor("Options (--option)", rows: $draft.options)
                    keyValueEditor("Labels (--label)", rows: $draft.labels)
                }
            }
            .formStyle(.grouped)

            VStack(alignment: .leading, spacing: 4) {
                Text("Command preview").font(.caption).foregroundStyle(.secondary)
                Text(actions.commandPreview(for: draft))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(CapsuleColors.activitySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Button("Cancel", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func create() {
        busy = true
        Task {
            let ok = await actions.create(draft: draft, against: existingNetworks)
            busy = false
            if ok { onClose() }
        }
    }

    /// A dynamic editor for `key=value` rows (used for both `--option` and `--label`).
    private func keyValueEditor(
        _ label: String, rows: Binding<[KeyValueRow]>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    rows.wrappedValue.append(KeyValueRow())
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help("Add a \(label.lowercased()) row")
            }
            ForEach(rows) { $row in
                HStack {
                    TextField("key", text: $row.key).textFieldStyle(.roundedBorder)
                    Text("=").foregroundStyle(.secondary)
                    TextField("value", text: $row.value).textFieldStyle(.roundedBorder)
                    Button {
                        rows.wrappedValue.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build — expect success.** `make build` → `Build complete!` with no errors.

- [ ] **Step 3: Commit.**

```bash
git add Sources/CapsuleUI/CreateNetworkSheet.swift
git commit -m "feat(networks): Create Network sheet with live subnet-conflict validation

Name + optional Subnet (CIDR hint + live overlap warning) and an Advanced disclosure
(IPv6 subnet, Internal toggle, plugin, --option/--label rows) with a live argv preview.
Create is disabled while a conflict stands. The sheet imports only CapsuleDomain + SwiftUI
and sources commandPreview/subnetConflictMessage/canCreate from NetworkActionsModel — it
never names NetworkConfiguration nor calls NetworkValidation.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 4.8: NetworkPruneSheet (UI)

**Files:**
- Create `Sources/CapsuleUI/NetworkPruneSheet.swift`

**Interfaces:**
- Consumes (Task 4.6): `NetworkActionsModel.computePruneTargets() -> [Network]`, `prune() -> PruneSummary`; (Task 4.1) `Network`.
- Produces: `struct NetworkPruneSheet` (used by Task 4.10).

> Verification: build-only (mirrors `ImagePruneSheet`), exercised in the Phase 6 GUI smoke. Imports only `CapsuleDomain` + `SwiftUI`; never names `NetworkConfiguration`.

**Steps:**

- [ ] **Step 1: Write the implementation.** Create `Sources/CapsuleUI/NetworkPruneSheet.swift`:

```swift
//
//  NetworkPruneSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The network Clean Up sheet: precompute a best-effort preview of zero-connection networks
//  (builtins excluded), then report the actual reclaimed result after running. Honest that
//  the runtime owns the final set — mirrors ImagePruneSheet.

import CapsuleDomain
import SwiftUI

struct NetworkPruneSheet: View {
    let actions: NetworkActionsModel
    let onClose: () -> Void

    @State private var targets: [CapsuleDomain.Network] = []
    @State private var isLoading = true
    @State private var isPruning = false
    @State private var resultMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Clean Up Networks", systemImage: "trash")
                .font(.headline)

            if let resultMessage {
                Text(resultMessage).font(.callout)
            } else if isLoading {
                ProgressView("Finding networks…")
            } else if targets.isEmpty {
                Text("No unused networks to remove.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(targets.count) network(s) will be removed:")
                    .font(.callout)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(targets) { network in
                            Text("• \(network.name)\(network.ipv4Subnet.map { "  \($0)" } ?? "")")
                                .font(.system(.callout, design: .monospaced))
                        }
                    }
                }
                .frame(maxHeight: 160)
                Text(
                    "This preview is best-effort; the runtime decides the final set. Builtin "
                        + "networks are never removed. The actual result is shown after cleanup."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button(resultMessage == nil ? "Cancel" : "Done", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if resultMessage == nil {
                    Button("Clean Up", role: .destructive) {
                        Task {
                            isPruning = true
                            let summary = await actions.prune()
                            resultMessage = summary.message
                            isPruning = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || isPruning)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { await reloadTargets() }
    }

    private func reloadTargets() async {
        isLoading = true
        targets = await actions.computePruneTargets()
        isLoading = false
    }
}
```

- [ ] **Step 2: Build — expect success.** `make build` → `Build complete!`.

- [ ] **Step 3: Commit.**

```bash
git add Sources/CapsuleUI/NetworkPruneSheet.swift
git commit -m "feat(networks): best-effort Network Clean Up sheet

Previews zero-connection networks (builtins excluded), labels the preview best-effort,
and shows the actual reclaimed result after running. Mirrors ImagePruneSheet.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 4.9: NetworkInspectorView (UI)

**Files:**
- Create `Sources/CapsuleUI/NetworkInspectorView.swift`

**Interfaces:**
- Consumes (Task 4.5): `NetworkBrowserModel.selection`, `selectedNetworks`, `inspect(name:)`; (Task 4.1) `Network`; (existing) `Pasteboard`, `JSONPrettyPrinter`.
- Produces: `struct NetworkInspectorView` (used by Task 4.11 inspector switch).

> Verification: build-only (mirrors `ImageInspectorView`), exercised in the Phase 6 GUI smoke. Imports only `AppKit` + `CapsuleDomain` + `SwiftUI` (AppKit/NSPasteboard is permitted in the UI layer); never names `NetworkConfiguration`.

**Steps:**

- [ ] **Step 1: Write the implementation.** Create `Sources/CapsuleUI/NetworkInspectorView.swift`:

```swift
//
//  NetworkInspectorView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The networks inspector: a Summary tab (mode, plugin, subnet/gateway/ipv6 as copyable
//  fields, internal/builtin flags, and the connected containers with a prominent count) plus
//  a Raw JSON tab fed by `network inspect`. The raw payload is always shown even when
//  decoding drifts, and is copyable. AppKit (NSPasteboard) is permitted in the UI layer.

import AppKit
import CapsuleDomain
import SwiftUI

struct NetworkInspectorView: View {
    let model: NetworkBrowserModel

    @State private var rawJSON = ""
    @State private var isLoadingRaw = false

    init(model: NetworkBrowserModel) {
        self.model = model
    }

    /// The single selected network, when exactly one row is selected.
    private var solo: Network? {
        guard model.selection.count == 1, let id = model.selection.first else { return nil }
        return model.selectedNetworks.first { $0.id == id }
    }

    var body: some View {
        TabView {
            summaryTab
                .tabItem { Label("Summary", systemImage: "info.circle") }
            rawTab
                .tabItem { Label("Raw JSON", systemImage: "curlybraces") }
        }
        .task(id: model.selection) { await loadRaw() }
    }

    // MARK: Summary

    @ViewBuilder
    private var summaryTab: some View {
        if model.selection.isEmpty {
            ContentUnavailableView(
                "No Selection", systemImage: "network",
                description: Text("Select a network to see its details."))
        } else if let network = solo {
            Form {
                Section("Network") {
                    LabeledContent("Name", value: network.name)
                    LabeledContent("Mode", value: network.mode ?? "—")
                    LabeledContent("Plugin", value: network.plugin ?? "—")
                    copyableField("IPv4 Subnet", value: network.ipv4Subnet)
                    copyableField("Gateway", value: network.ipv4Gateway)
                    copyableField("IPv6 Subnet", value: network.ipv6Subnet)
                    if network.internal {
                        LabeledContent("Connectivity", value: "Internal (no external access)")
                    }
                    if network.isBuiltin {
                        LabeledContent("State") {
                            Label("Builtin (protected)", systemImage: "lock.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let created = network.createdAt {
                        LabeledContent("Created") { Text(created, format: .dateTime) }
                    }
                }

                Section("Connected Containers (\(network.connectedContainers.count))") {
                    if network.connectedContainers.isEmpty {
                        Text("No connected containers.").foregroundStyle(.secondary)
                    } else {
                        ForEach(network.connectedContainers, id: \.self) { name in
                            Text(name)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "\(model.selection.count) Networks Selected", systemImage: "network",
                description: Text("Select a single network to see its details."))
        }
    }

    /// A labeled value with a copy button when present; an em dash when absent.
    @ViewBuilder
    private func copyableField(_ label: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label) {
                HStack(spacing: 6) {
                    Text(value).font(.system(.body, design: .monospaced))
                    Button {
                        Pasteboard.copy(value)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy \(label) (\(value))")
                }
            }
        } else {
            LabeledContent(label, value: "—")
        }
    }

    // MARK: Raw JSON

    @ViewBuilder
    private var rawTab: some View {
        if solo == nil {
            ContentUnavailableView(
                "No Selection", systemImage: "curlybraces",
                description: Text("Select a single network to inspect its raw JSON."))
        } else {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        Pasteboard.copy(rawJSON)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .disabled(rawJSON.isEmpty)
                }
                .padding(8)

                Divider()

                ScrollView([.vertical, .horizontal]) {
                    Text(rawJSON.isEmpty ? "No raw payload available." : rawJSON)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .overlay {
                    if isLoadingRaw { ProgressView() }
                }
            }
        }
    }

    // MARK: Actions

    private func loadRaw() async {
        guard let network = solo else {
            rawJSON = ""
            return
        }
        isLoadingRaw = true
        let inspection = await model.inspect(name: network.name)
        rawJSON = JSONPrettyPrinter.prettyPrint(inspection.rawJSON)
        isLoadingRaw = false
    }
}
```

- [ ] **Step 2: Build — expect success.** `make build` → `Build complete!`.

- [ ] **Step 3: Commit.**

```bash
git add Sources/CapsuleUI/NetworkInspectorView.swift
git commit -m "feat(networks): Network inspector (Summary IPAM + connected containers, Raw JSON)

Summary shows mode/plugin/subnet/gateway/ipv6 as copyable fields plus the connected
containers with a prominent count; Raw JSON tab fed by network inspect (copyable).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 4.10: NetworkListView (UI)

**Files:**
- Create `Sources/CapsuleUI/NetworkListView.swift`

**Interfaces:**
- Consumes (Tasks 4.5/4.6): `NetworkBrowserModel` (`rows`, `selection`, `allNetworks`, `loadState`, `isEmptyButHealthy`, `noMatches`, `refresh()`), `NetworkActionsModel.delete(name:)`/`deleteAll(names:)`; (Task 4.4) `ConfirmationRequest.deleteNetwork(name:isBuiltin:attachments:)`; (Phase 2) `AttachmentIndex(volumes:networks:)`; (Tasks 4.7/4.8) `CreateNetworkSheet`, `NetworkPruneSheet`; (existing) `ConfirmationSheet`, `Pasteboard`, `Network`.
- Produces: `struct NetworkListView`, `enum NetworkSheet` (used by Task 4.11 routing).

> Verification: build-only (mirrors `ImageListView`), exercised in the Phase 6 GUI smoke. Imports only `AppKit` + `CapsuleDomain` + `SwiftUI`; never names `NetworkConfiguration`. **Builtin protection lives here:** the lock column, the disabled single-row Delete for builtins, and the `filter { !$0.isBuiltin }` before any delete/bulk path.

**Steps:**

- [ ] **Step 1: Write the implementation.** Create `Sources/CapsuleUI/NetworkListView.swift`:

```swift
//
//  NetworkListView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The networks content column: a Table backed by NetworkBrowserModel with search, a context
//  menu (single-row Copy/Delete), and a toolbar (Create…, Clean Up = prune, Refresh). Builtin
//  networks show a lock and a disabled Delete and are excluded from bulk delete. Destructive
//  actions always confirm via the generic ConfirmationSheet.

import AppKit
import CapsuleDomain
import SwiftUI

struct NetworkListView: View {
    @Bindable var model: NetworkBrowserModel
    let actions: NetworkActionsModel

    @State private var activeSheet: NetworkSheet?

    init(model: NetworkBrowserModel, actions: NetworkActionsModel) {
        self.model = model
        self.actions = actions
    }

    var body: some View {
        content
            .searchable(text: $model.searchText, prompt: "Search networks")
            .toolbar { toolbarContent }
            .task { await model.refresh() }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .create:
                    CreateNetworkSheet(
                        actions: actions, existingNetworks: model.allNetworks,
                        onClose: { activeSheet = nil })
                case .prune:
                    NetworkPruneSheet(actions: actions, onClose: { activeSheet = nil })
                case let .confirm(request):
                    ConfirmationSheet(
                        request: request,
                        onConfirm: { req in
                            activeSheet = nil
                            performConfirmed(req)
                        }, onCancel: { activeSheet = nil })
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading:
            ProgressView("Loading networks…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .unavailable(detail):
            ContentUnavailableView {
                Label(detail.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(detail.explanation)
            }
        case .loaded:
            if model.isEmptyButHealthy {
                ContentUnavailableView {
                    Label("No networks yet", systemImage: "network")
                } description: {
                    Text("Networks you create will appear here.")
                }
            } else {
                table
            }
        }
    }

    private var table: some View {
        Table(model.rows, selection: $model.selection) {
            TableColumn("") { network in
                if network.isBuiltin {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .help("Builtin network (protected)")
                }
            }
            .width(18)

            TableColumn("Name") { Text($0.name) }
            TableColumn("Subnet") { network in
                Text(network.ipv4Subnet ?? "—")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            TableColumn("Connections") { network in
                Text("\(network.connectedContainers.count)")
                    .foregroundStyle(.secondary)
            }
            TableColumn("Created") { network in
                if let created = network.createdAt {
                    Text(created, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu(forSelectionType: Network.ID.self) { ids in
            rowMenu(for: ids)
        }
        .onDeleteCommand { requestDelete(ids: model.selection) }
        .overlay {
            if model.noMatches { ContentUnavailableView.search }
        }
    }

    @ViewBuilder
    private func rowMenu(for ids: Set<Network.ID>) -> some View {
        let targets = networks(for: ids)
        let deletable = targets.filter { !$0.isBuiltin }
        if let single = targets.first, targets.count == 1 {
            Button("Copy Name") { Pasteboard.copy(single.name) }
            if let subnet = single.ipv4Subnet {
                Button("Copy Subnet") { Pasteboard.copy(subnet) }
            }
            Divider()
        }
        Button("Delete…", role: .destructive) { requestDelete(ids: ids) }
            .disabled(deletable.isEmpty)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                activeSheet = .create
            } label: {
                Label("Create", systemImage: "plus")
            }
            .help("Create a network")

            Button {
                activeSheet = .prune
            } label: {
                Label("Clean Up", systemImage: "trash")
            }
            .help("Remove networks with no connections")

            Button {
                Task { await model.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Reload networks")
        }
    }

    // MARK: - Destructive actions

    /// Builtin networks are filtered out (protected). A single non-builtin target uses the
    /// domain builder (which embeds the connected-container warning); a multi-select builds a
    /// combined confirmation inline.
    private func requestDelete(ids: Set<Network.ID>) {
        let targets = networks(for: ids).filter { !$0.isBuiltin }
        guard !targets.isEmpty else { return }
        if targets.count == 1 {
            let network = targets[0]
            if let request = ConfirmationRequest.deleteNetwork(
                name: network.name, isBuiltin: network.isBuiltin,
                attachments: attachmentIndex())
            {
                activeSheet = .confirm(request)
            }
        } else {
            let names = targets.map(\.name)
            activeSheet = .confirm(
                ConfirmationRequest(
                    title: "Delete \(names.count) networks?",
                    message: "This permanently removes the selected networks. A network with "
                        + "connected containers can't be removed until they detach.",
                    confirmTitle: "Delete", targetIDs: names, kind: .deleteNetwork))
        }
    }

    private func performConfirmed(_ request: ConfirmationRequest) {
        switch request.kind {
        case .deleteNetwork:
            let names = request.targetIDs
            Task {
                if names.count == 1 {
                    await actions.delete(name: names[0])
                } else {
                    await actions.deleteAll(names: names)
                }
            }
        default:
            break  // other kinds are not raised by the networks surface
        }
    }

    /// Builds an attachment index from the already-stamped browser rows, so the delete
    /// confirmation can name connected containers without another backend round-trip.
    private func attachmentIndex() -> AttachmentIndex {
        var networks: [String: [String]] = [:]
        for network in model.allNetworks {
            networks[network.name] = network.connectedContainers
        }
        return AttachmentIndex(volumes: [:], networks: networks)
    }

    private func networks(for ids: Set<Network.ID>) -> [Network] {
        model.allNetworks.filter { ids.contains($0.id) }
    }
}

/// Which network sheet is presented.
enum NetworkSheet: Identifiable {
    case create
    case prune
    case confirm(ConfirmationRequest)

    var id: String {
        switch self {
        case .create: return "create"
        case .prune: return "prune"
        case let .confirm(request): return "confirm-\(request.id)"
        }
    }
}
```

- [ ] **Step 2: Build — expect success.** `make build` → `Build complete!`.

- [ ] **Step 3: Commit.**

```bash
git add Sources/CapsuleUI/NetworkListView.swift
git commit -m "feat(networks): NetworkListView (table, context menu, toolbar, builtin lock)

Search + context-menu Copy/Delete + toolbar Create/Clean Up/Refresh. Builtin networks
show a lock and a disabled Delete and are excluded from bulk delete; all destructive
actions confirm via the generic ConfirmationSheet.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 4.11: Wiring + composition test (additive; no gating logic)

**Files:**
- Modify `Sources/CapsuleUI/ContentColumnView.swift` (add two `let` properties; add a `.networks` switch arm)
- Modify `Sources/CapsuleUI/AppShellView.swift` (add two `@Bindable` properties + init params/assignments; add a network notice block; add two args to the `ContentColumnView(...)` call; add a `.networks` inspector arm)
- Modify `Sources/CapsuleUI/RootView.swift` (add two `let` properties + init params/assignments; add two args to the `AppShellView(...)` call)
- Modify `Sources/CapsuleApp/AppEnvironment.swift` (add two struct props + init params/assignments; build both models in `live()`; add two args to the returned `AppEnvironment(...)`)
- Modify `Sources/CapsuleApp/CapsuleScene.swift` (add two `@State` props + init assignments; add two args to the `RootView(...)` call)
- Modify `Tests/CapsuleUnitTests/CompositionTests.swift` (append a test)

**Interfaces:**
- Consumes (Tasks 4.5/4.6/4.9/4.10): `NetworkBrowserModel`, `NetworkActionsModel`, `NetworkListView`, `NetworkInspectorView`; (existing) `ErrorNormalizer.normalize`, `LifecycleNoticeView`.
- Produces: `AppEnvironment.networkBrowserModel`/`networkActionsModel`; the `.networks` routing arm in `ContentColumnView`; the `.networks` inspector arm + a network `LifecycleNotice` overlay in `AppShellView`.

> **No gating here.** This phase adds ONLY the `.networks` routing + inspector arms + models. Family-level capability gating (`SystemHealth.supports`, the sidebar's `requiredFeature`, the `ContentColumnView` `health.isRunning` guard) is owned by Phase 6 — do not add or modify any gating flag.
> **ADDITIVE — earlier phases ran first.** By the time this task executes, Phase 3 has already added its volume models/props/arms to all of these files. Every edit below INSERTS lines; it never rewrites a whole `switch`, `enum`, init, or struct body. Anchor each insertion on the corresponding `imageActionsModel`/`imageBrowserModel` member (image members predate M8 and are stable in all phases).

**Steps:**

- [ ] **Step 1: Write the failing composition test.** Append to `Tests/CapsuleUnitTests/CompositionTests.swift` (before the final `}`, after any volume composition test Phase 3 appended):

```swift
    @MainActor
    func testLiveEnvironmentBuildsNetworkModels() {
        let environment = AppEnvironment.live()

        XCTAssertEqual(environment.networkBrowserModel.loadState, .idle)
        XCTAssertTrue(environment.networkBrowserModel.allNetworks.isEmpty)
        XCTAssertTrue(environment.networkActionsModel.busy.isEmpty)
        XCTAssertNil(environment.networkActionsModel.notice)
    }
```

- [ ] **Step 2: Run it — expect a build failure.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CompositionTests` → `error: value of type 'AppEnvironment' has no member 'networkBrowserModel'`.

- [ ] **Step 3: Add the models to `AppEnvironment` (additive).** In `Sources/CapsuleApp/AppEnvironment.swift`, immediately after the existing `public var imageActionsModel: ImageActionsModel` property, INSERT:

```swift
    public var networkBrowserModel: NetworkBrowserModel
    public var networkActionsModel: NetworkActionsModel
```

In `init`, immediately after the existing `imageActionsModel: ImageActionsModel,` parameter, INSERT:

```swift
        networkBrowserModel: NetworkBrowserModel,
        networkActionsModel: NetworkActionsModel,
```

and immediately after the existing `self.imageActionsModel = imageActionsModel` assignment, INSERT:

```swift
        self.networkBrowserModel = networkBrowserModel
        self.networkActionsModel = networkActionsModel
```

In `live()`, immediately after the existing `imageActionsModel` declaration block, INSERT:

```swift
        let networkBrowserModel = NetworkBrowserModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) }
        )
        let networkActionsModel = NetworkActionsModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            reloadList: { await networkBrowserModel.refresh() }
        )
```

and in the returned `AppEnvironment(...)`, immediately after the existing `imageActionsModel: imageActionsModel,` argument, INSERT:

```swift
            networkBrowserModel: networkBrowserModel,
            networkActionsModel: networkActionsModel,
```

- [ ] **Step 4: Thread through `CapsuleScene` (additive).** In `Sources/CapsuleApp/CapsuleScene.swift`, immediately after the existing `@State private var imageActionsModel: ImageActionsModel`, INSERT:

```swift
    @State private var networkBrowserModel: NetworkBrowserModel
    @State private var networkActionsModel: NetworkActionsModel
```

In `init(environment:)`, immediately after the existing `self._imageActionsModel = State(initialValue: environment.imageActionsModel)`, INSERT:

```swift
        self._networkBrowserModel = State(initialValue: environment.networkBrowserModel)
        self._networkActionsModel = State(initialValue: environment.networkActionsModel)
```

In the `RootView(...)` call, immediately after the existing `imageActionsModel: imageActionsModel,` argument, INSERT:

```swift
                networkBrowserModel: networkBrowserModel,
                networkActionsModel: networkActionsModel,
```

- [ ] **Step 5: Thread through `RootView` (additive).** In `Sources/CapsuleUI/RootView.swift`, immediately after the existing `private let imageActionsModel: ImageActionsModel`, INSERT:

```swift
    private let networkBrowserModel: NetworkBrowserModel
    private let networkActionsModel: NetworkActionsModel
```

In `init`, immediately after the existing `imageActionsModel: ImageActionsModel,` parameter, INSERT:

```swift
        networkBrowserModel: NetworkBrowserModel,
        networkActionsModel: NetworkActionsModel,
```

immediately after the existing `self.imageActionsModel = imageActionsModel`, INSERT:

```swift
        self.networkBrowserModel = networkBrowserModel
        self.networkActionsModel = networkActionsModel
```

and in the `AppShellView(...)` call in `body`, immediately after the existing `imageActionsModel: imageActionsModel,` argument, INSERT:

```swift
            networkBrowserModel: networkBrowserModel,
            networkActionsModel: networkActionsModel,
```

- [ ] **Step 6: Thread through `AppShellView` (additive) + render the notice.** In `Sources/CapsuleUI/AppShellView.swift`, immediately after the existing `@Bindable var imageActionsModel: ImageActionsModel`, INSERT:

```swift
    @Bindable var networkBrowserModel: NetworkBrowserModel
    @Bindable var networkActionsModel: NetworkActionsModel
```

In `init`, immediately after the existing `imageActionsModel: ImageActionsModel,` parameter, INSERT:

```swift
        networkBrowserModel: NetworkBrowserModel,
        networkActionsModel: NetworkActionsModel,
```

immediately after the existing `self.imageActionsModel = imageActionsModel`, INSERT:

```swift
        self.networkBrowserModel = networkBrowserModel
        self.networkActionsModel = networkActionsModel
```

**Render the notice (HIGH fix):** immediately after the existing `imageActionsModel` notice block in `detailColumn` (the `if let notice = imageActionsModel.notice { … }`), INSERT a mirroring network notice block:

```swift
            if let notice = networkActionsModel.notice {
                LifecycleNoticeView(
                    notice: notice,
                    onAction: { _ in networkActionsModel.notice = nil },
                    onForceStop: { _ in networkActionsModel.notice = nil },
                    onDismiss: { networkActionsModel.notice = nil }
                )
                .padding(.top, 6)
            }
```

In the `ContentColumnView(...)` call, immediately after the existing `imageActionsModel: imageActionsModel,` argument, INSERT:

```swift
                networkBrowserModel: networkBrowserModel,
                networkActionsModel: networkActionsModel,
```

In the `.inspector` switch, add a `.networks` arm (additive — its position relative to Phase 3's `.volumes` arm is irrelevant). Immediately after the existing `case .images: ImageInspectorView(model: imageBrowserModel)` arm, INSERT:

```swift
                case .networks:
                    NetworkInspectorView(model: networkBrowserModel)
```

- [ ] **Step 7: Route `.networks` in `ContentColumnView` (additive).** In `Sources/CapsuleUI/ContentColumnView.swift`, immediately after the existing `let imageActionsModel: ImageActionsModel`, INSERT:

```swift
    let networkBrowserModel: NetworkBrowserModel
    let networkActionsModel: NetworkActionsModel
```

and in `runningContent`'s switch, INSERT a `.networks` arm before `default:` (additive — Phase 3's `.volumes` arm is also present; do not remove it or the `default:` arm):

```swift
        case .networks:
            NetworkListView(model: networkBrowserModel, actions: networkActionsModel)
```

- [ ] **Step 8: Run the composition test + build — expect PASS.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CompositionTests` → all pass (incl. the new test). Then `make build` → `Build complete!`.

- [ ] **Step 9: Full check + format.** Run `make check` (lint + arch guard + license headers) → passes (confirms `CapsuleUI` still imports no backend module — the new UI files import only `AppKit`/`CapsuleDomain`/`SwiftUI` — and the new Domain files import only `CapsuleBackend`/`Observation`/`Foundation`). Run `make test` → green. If swift-format flags anything, run `make format`.

- [ ] **Step 10: Commit.**

```bash
git add Sources/CapsuleUI/ContentColumnView.swift Sources/CapsuleUI/AppShellView.swift \
        Sources/CapsuleUI/RootView.swift Sources/CapsuleApp/AppEnvironment.swift \
        Sources/CapsuleApp/CapsuleScene.swift Tests/CapsuleUnitTests/CompositionTests.swift
git commit -m "feat(networks): wire NetworkBrowserModel/NetworkActionsModel into the shell

ContentColumnView routes .networks to NetworkListView; AppShellView adds the inspector
arm + renders a network LifecycleNotice (mirrors the image notice block); AppEnvironment
.live() builds both models (reloadList -> browser refresh) and threads them through
RootView/CapsuleScene. All edits additive over Phase 3; no capability-gating logic (Phase 6
owns gating).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```


---

## Phase 5: Local DNS in Settings (privileged handoff)

This phase delivers the full DNS surface of Milestone 8 (spec §7): the `DNSDomain` domain model, the `@Observable @MainActor` `DNSModel` (mirroring `RegistriesModel`), `DNSDraft` + validation, the `NetworkingView` preferences pane (with an Add Domain sheet and per-row Delete that hand off to a privileged `sudo` Terminal session rather than running in-process), the new Networking tab in `PreferencesView`, the `CapsuleScene` threading, and the `AppEnvironment` wiring (`openPrivilegedCommandInTerminalApp`, the `runPrivilegedInTerminal` closure, and the previously-stubbed `.grantPermission(.administrator)` recovery handler as a guidance-only safety net). Phase 5 **owns no `ErrorNormalizer` edit**: the administrator-signature mapping — `BackendError.nonZeroExit` whose stderr/command contains `try sudo?` / `must run as an administrator` → `CapsuleError.permissionRequired(kind: .administrator, …)`, checked before the daemon signatures — is owned exclusively by **Phase 1 Task 1.6** (`Sources/CapsuleDiagnostics/ErrorNormalization.swift` + its `ErrorNormalizationTests`). Phase 5 only **consumes** that mapping: the `DNSModel.refresh` failure path runs it through the injected normalizer, so the end-to-end "DNS never fails silently" coverage lives in this phase as a `DNSModel` test that surfaces `permissionRequired(.administrator)` (`testRefreshSurfacesPermissionRequired`). It **consumes from Phase 1** the backend pieces `DNSConfiguration` (`.arguments` / `.deleteArguments`), `DNSDomainSummary`, `ContainerBackend.listDNSDomains() async throws -> [DNSDomainSummary]`, the matching `MockBackend(dnsDomains:)` seed + `listDNSDomains()` (mirroring `registries:` / `listRegistries()`), and the Phase 1 Task 1.6 `permissionRequired(.administrator)` mapping. Nothing in later phases consumes this phase; it is a leaf in the M8 graph.

> **CONTRACT DEPENDENCY (Phase 1):** these DNS backend types/methods are produced by Phase 1 and locked in the shared contract (§4.1–§4.3, §1.7): `public struct DNSConfiguration` with `init(domain:localhostIP:)`, `var arguments: [String]` (`["system","dns","create"]` + optional `["--localhost", ip]` + `[domain]`) and `var deleteArguments: [String]` (`["system","dns","delete", domain]`); `public struct DNSDomainSummary` with `init(domain:localhostIP:)` and `id == domain`; `func listDNSDomains() async throws -> [DNSDomainSummary]` on `ContainerBackend`; on `MockBackend` a `dnsDomains: [DNSDomainSummary] = []` init param returned by `listDNSDomains()` (with the existing `failure: BackendError?` injection); and the Phase 1 Task 1.6 `ErrorNormalizer` administrator-signature mapping to `permissionRequired(.administrator)` (detail title `"Administrator access required"`, recovery actions include `.grantPermission(.administrator)`). This phase compiles only once those land.

---

### Task 5.1: `DNSDomain` + `DNSDraft` domain value types

Adds the domain's read model of a local DNS domain (`DNSDomain`, built from Phase 1's `DNSDomainSummary`) and the editable form behind the Add Domain sheet (`DNSDraft`). Pure, UI-free, Process-free.

**Files:**
- Create: `Sources/CapsuleDomain/DNSDomain.swift`
- Create: `Tests/CapsuleUnitTests/DNSDomainTests.swift`

**Interfaces:**
- Consumes: `DNSDomainSummary(domain:localhostIP:)` with `id == domain` (Phase 1, `CapsuleBackend`).
- Produces: `public struct DNSDomain: Sendable, Equatable, Identifiable` with `var domain: String`, `var localhostIP: String?`, `var id: String { domain }`, `init(domain:localhostIP:)`, `init(summary: DNSDomainSummary)`; and `public struct DNSDraft: Sendable, Equatable` with `var domain: String`, `var localhostIP: String`, `init(domain: String = "", localhostIP: String = "")`. Consumed by Tasks 5.2–5.6.

**Steps:**

- [ ] **Step 1: Write the failing test.** Create `Tests/CapsuleUnitTests/DNSDomainTests.swift`:

```swift
//
//  DNSDomainTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

final class DNSDomainTests: XCTestCase {
    func testInitFromSummaryMapsFields() {
        let summary = DNSDomainSummary(domain: "test", localhostIP: "127.0.0.1")
        let domain = DNSDomain(summary: summary)
        XCTAssertEqual(domain.domain, "test")
        XCTAssertEqual(domain.localhostIP, "127.0.0.1")
        XCTAssertEqual(domain.id, "test")
    }

    func testInitFromSummaryWithoutIP() {
        let domain = DNSDomain(summary: DNSDomainSummary(domain: "app.test"))
        XCTAssertEqual(domain.domain, "app.test")
        XCTAssertNil(domain.localhostIP)
    }

    func testDraftDefaultsAreEmpty() {
        let draft = DNSDraft()
        XCTAssertTrue(draft.domain.isEmpty)
        XCTAssertTrue(draft.localhostIP.isEmpty)
    }
}
```

- [ ] **Step 2: Run it and confirm it fails.** Command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DNSDomainTests`
  Expected FAIL: compile error — `cannot find 'DNSDomain' in scope` / `cannot find 'DNSDraft' in scope`.

- [ ] **Step 3: Create the value types.** Create `Sources/CapsuleDomain/DNSDomain.swift`:

```swift
//
//  DNSDomain.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. The domain's view
//  of a configured local DNS domain and the editable draft behind the Add Domain sheet.

import CapsuleBackend
import Foundation

/// A configured local DNS domain (apple/container's `system dns` resolves names under it).
public struct DNSDomain: Sendable, Equatable, Identifiable {
    public var domain: String
    public var localhostIP: String?
    public var id: String { domain }

    public init(domain: String, localhostIP: String? = nil) {
        self.domain = domain
        self.localhostIP = localhostIP
    }

    public init(summary: DNSDomainSummary) {
        self.init(domain: summary.domain, localhostIP: summary.localhostIP)
    }
}

/// The editable form behind the Add Domain sheet: a domain name and an optional localhost IP.
public struct DNSDraft: Sendable, Equatable {
    public var domain: String
    public var localhostIP: String

    public init(domain: String = "", localhostIP: String = "") {
        self.domain = domain
        self.localhostIP = localhostIP
    }
}
```

- [ ] **Step 4: Run it and confirm it passes.** Command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DNSDomainTests`
  Expected PASS: all three `DNSDomainTests` pass.

- [ ] **Step 5: Commit.**

```bash
make format
git add Sources/CapsuleDomain/DNSDomain.swift Tests/CapsuleUnitTests/DNSDomainTests.swift
git commit -m "feat(m8): add DNSDomain + DNSDraft domain value types

DNSDomain mirrors the backend DNSDomainSummary; DNSDraft is the editable
form for the Add Domain sheet. Pure, UI-free, Process-free.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 5.2: `DNSModel` + `DNSLoadState` — unprivileged list / refresh

Adds the `@Observable @MainActor` model that mirrors `RegistriesModel`: it lists DNS domains (the only unprivileged DNS operation), distinguishing an empty `[]` (`.loaded`, rendered as "No local DNS domains") from a load failure (`.unavailable(ErrorDetail)`), and surfaces `permissionRequired(.administrator)` through the injected normalizer — the mapping is owned by **Phase 1 Task 1.6**; this model only consumes it. The create/delete handoff methods land in Task 5.3.

**Files:**
- Create: `Sources/CapsuleDomain/DNSModel.swift` (init + `refresh()`; the `runPrivilegedInTerminal`/`onActivity` closures are stored here and consumed in Task 5.3)
- Create: `Tests/CapsuleUnitTests/DNSModelTests.swift`

**Interfaces:**
- Consumes: `ContainerBackend.listDNSDomains() async throws -> [DNSDomainSummary]` and `MockBackend(dnsDomains:)` + `failure` (Phase 1); `DNSDomain(summary:)` (Task 5.1); `SystemStatusModel.defaultNormalize` (`nonisolated static let @Sendable (any Error) -> CapsuleError`); `ErrorDetail`; `LifecycleNotice`; `ErrorNormalizer.normalize(_:)` (Phase 1 Task 1.6, via test).
- Produces: `public enum DNSLoadState: Sendable, Equatable { case idle, loading, loaded; case unavailable(ErrorDetail) }`; `@MainActor @Observable public final class DNSModel` with `public private(set) var domains: [DNSDomain]`, `public private(set) var loadState: DNSLoadState`, `public var notice: LifecycleNotice?`, `init(backend:normalize:onActivity:runPrivilegedInTerminal:)` (the `runPrivilegedInTerminal: @escaping @MainActor ([String]) -> Void` has **no default**; the rest match `RegistriesModel`), and `func refresh() async`. Consumed by Tasks 5.3–5.6.

**Steps:**

- [ ] **Step 1: Write the failing tests.** Create `Tests/CapsuleUnitTests/DNSModelTests.swift`:

```swift
//
//  DNSModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Local DNS domain management: an unprivileged list (empty vs. failure) plus create/delete
//  that hand the privileged argv to an injected Terminal closure — never the backend.

import CapsuleBackend
import CapsuleDiagnostics
import XCTest

@testable import CapsuleDomain

@MainActor
final class DNSModelTests: XCTestCase {
    func testRefreshLoadsDomains() async {
        let backend = MockBackend(
            dnsDomains: [DNSDomainSummary(domain: "test", localhostIP: "127.0.0.1")])
        let model = DNSModel(backend: backend, runPrivilegedInTerminal: { _ in })

        await model.refresh()

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.domains.map(\.domain), ["test"])
        XCTAssertEqual(model.domains.first?.localhostIP, "127.0.0.1")
    }

    func testRefreshEmptyIsLoadedNotUnavailable() async {
        let backend = MockBackend(dnsDomains: [])
        let model = DNSModel(backend: backend, runPrivilegedInTerminal: { _ in })

        await model.refresh()

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertTrue(model.domains.isEmpty, "an empty list is loaded, rendered 'No local DNS domains'")
    }

    func testRefreshFailureIsUnavailableNotEmpty() async {
        let backend = MockBackend(dnsDomains: [])
        backend.failure = BackendError.nonZeroExit(
            command: "container system dns list", code: 1, stderr: "Connection refused")
        let model = DNSModel(backend: backend, runPrivilegedInTerminal: { _ in })

        await model.refresh()

        guard case .unavailable = model.loadState else {
            return XCTFail("a load failure must be .unavailable, not an empty list")
        }
    }

    func testRefreshSurfacesPermissionRequired() async {
        let backend = MockBackend(dnsDomains: [])
        backend.failure = BackendError.nonZeroExit(
            command: "container system dns list", code: 1,
            stderr: "must run as an administrator")
        let model = DNSModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            runPrivilegedInTerminal: { _ in })

        await model.refresh()

        guard case let .unavailable(detail) = model.loadState else {
            return XCTFail("expected .unavailable")
        }
        XCTAssertEqual(detail.title, "Administrator access required")
        XCTAssertTrue(detail.recoveryActions.contains(.grantPermission(.administrator)))
    }
}
```

- [ ] **Step 2: Run it and confirm it fails.** Command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DNSModelTests`
  Expected FAIL: compile error — `cannot find 'DNSModel' in scope`.

- [ ] **Step 3: Create the model (list path only).** Create `Sources/CapsuleDomain/DNSModel.swift`:

```swift
//
//  DNSModel.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`. Local DNS domain
//  management for the Networking preferences pane. Listing is unprivileged; create and delete
//  always require administrator rights, so they are NOT attempted in-process — they build the
//  argv and hand it to an injected privileged-Terminal closure (the App layer prefixes
//  `sudo`). The in-process safety net for an admin rejection on the list path is
//  `permissionRequired(.administrator)`, produced by the injected normalizer (the mapping is
//  owned by Phase 1's ErrorNormalizer; this model only consumes it).

import CapsuleBackend
import Foundation
import Observation

/// The load state of the DNS domain list, distinguishing a down service from no domains.
public enum DNSLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case unavailable(ErrorDetail)
}

@MainActor
@Observable
public final class DNSModel {
    public private(set) var domains: [DNSDomain] = []
    public private(set) var loadState: DNSLoadState = .idle
    public var notice: LifecycleNotice?

    private let backend: any ContainerBackend
    private let normalize: @Sendable (any Error) -> CapsuleError
    private let onActivity: @MainActor (String) -> Void
    private let runPrivilegedInTerminal: @MainActor ([String]) -> Void

    public init(
        backend: any ContainerBackend,
        normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel
            .defaultNormalize,
        onActivity: @escaping @MainActor (String) -> Void = { _ in },
        runPrivilegedInTerminal: @escaping @MainActor ([String]) -> Void
    ) {
        self.backend = backend
        self.normalize = normalize
        self.onActivity = onActivity
        self.runPrivilegedInTerminal = runPrivilegedInTerminal
    }

    /// Lists the configured local DNS domains. This is the only unprivileged DNS operation.
    /// An empty result is `.loaded` with no domains ("No local DNS domains"); a thrown error
    /// is `.unavailable` so the pane never confuses a down service with an empty list.
    public func refresh() async {
        loadState = .loading
        do {
            let summaries = try await backend.listDNSDomains()
            domains = summaries.map(DNSDomain.init(summary:))
            loadState = .loaded
        } catch {
            domains = []
            loadState = .unavailable(normalize(error).detail)
        }
    }
}
```

> The `onActivity` and `runPrivilegedInTerminal` closures are stored now and consumed by `addDomain`/`deleteDomain` in Task 5.3. (Swift emits no warning for an as-yet-unused stored `let`.)

- [ ] **Step 4: Run it and confirm it passes.** Command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DNSModelTests`
  Expected PASS: all four refresh tests pass (the last one exercises Phase 1 Task 1.6's administrator mapping end-to-end through the injected normalizer).

- [ ] **Step 5: Commit.**

```bash
make format
git add Sources/CapsuleDomain/DNSModel.swift Tests/CapsuleUnitTests/DNSModelTests.swift
git commit -m "feat(m8): add DNSModel.refresh (unprivileged list, empty vs failure)

Mirrors RegistriesModel: an empty list is .loaded ('No local DNS
domains'); a thrown error is .unavailable. A 'must run as an
administrator' failure surfaces as permissionRequired via the injected
normalizer (mapping owned by Phase 1).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 5.3: `DNSModel` create/delete handoff + draft validation

Adds `addDomain` (validate → hand off `DNSConfiguration.arguments`) and `deleteDomain` (hand off `DNSConfiguration(domain:).deleteArguments`). Neither touches the backend — admin is always required, so both build the argv and pass it straight to the injected `runPrivilegedInTerminal` closure (the App layer prefixes `sudo`). Validation rejects an empty/malformed domain and a malformed optional IPv4.

**Files:**
- Modify: `Sources/CapsuleDomain/DNSModel.swift` (add `addDomain`, `deleteDomain`, `validatedConfiguration`, and the two private validators after `refresh()`)
- Modify: `Tests/CapsuleUnitTests/DNSModelTests.swift` (append handoff + validation tests)

**Interfaces:**
- Consumes: `DNSConfiguration(domain:localhostIP:)` with `var arguments: [String]` and `var deleteArguments: [String]` (Phase 1, `CapsuleBackend`); `DNSDraft` (Task 5.1); `CapsuleError.invalidInput(field:message:)`.
- Produces: `@discardableResult public func addDomain(_ draft: DNSDraft) -> Result<Void, CapsuleError>`; `public func deleteDomain(_ domain: String)`; `func validatedConfiguration(_ draft: DNSDraft) -> Result<DNSConfiguration, CapsuleError>`. Consumed by `NetworkingView`/`AddDNSDomainSheet` (Task 5.4).

**Steps:**

- [ ] **Step 1: Write the failing tests.** Append to `Tests/CapsuleUnitTests/DNSModelTests.swift` (before the final closing brace):

```swift
    func testAddDomainHandsOffCreateArgvWithLocalhost() {
        var captured: [[String]] = []
        let model = DNSModel(backend: MockBackend(), runPrivilegedInTerminal: { captured.append($0) })

        let result = model.addDomain(DNSDraft(domain: "test", localhostIP: "127.0.0.1"))

        guard case .success = result else { return XCTFail("expected success") }
        XCTAssertEqual(captured, [["system", "dns", "create", "--localhost", "127.0.0.1", "test"]])
    }

    func testAddDomainWithoutIPOmitsLocalhostFlag() {
        var captured: [[String]] = []
        let model = DNSModel(backend: MockBackend(), runPrivilegedInTerminal: { captured.append($0) })

        let result = model.addDomain(DNSDraft(domain: "test", localhostIP: "   "))

        guard case .success = result else { return XCTFail("expected success") }
        XCTAssertEqual(captured, [["system", "dns", "create", "test"]])
    }

    func testAddDomainEmptyNameFailsValidationWithoutHandoff() {
        var captured: [[String]] = []
        let model = DNSModel(backend: MockBackend(), runPrivilegedInTerminal: { captured.append($0) })

        let result = model.addDomain(DNSDraft(domain: "   ", localhostIP: ""))

        guard case let .failure(.invalidInput(field, _)) = result else {
            return XCTFail("expected .invalidInput for an empty domain")
        }
        XCTAssertEqual(field, "domain")
        XCTAssertTrue(captured.isEmpty, "an invalid draft must not hand off")
    }

    func testAddDomainMalformedNameFailsValidation() {
        var captured: [[String]] = []
        let model = DNSModel(backend: MockBackend(), runPrivilegedInTerminal: { captured.append($0) })

        let result = model.addDomain(DNSDraft(domain: "bad domain!", localhostIP: ""))

        guard case let .failure(.invalidInput(field, _)) = result else {
            return XCTFail("expected .invalidInput for a malformed domain")
        }
        XCTAssertEqual(field, "domain")
        XCTAssertTrue(captured.isEmpty)
    }

    func testAddDomainInvalidIPFailsValidation() {
        var captured: [[String]] = []
        let model = DNSModel(backend: MockBackend(), runPrivilegedInTerminal: { captured.append($0) })

        let result = model.addDomain(DNSDraft(domain: "test", localhostIP: "999.1.1.1"))

        guard case let .failure(.invalidInput(field, _)) = result else {
            return XCTFail("expected .invalidInput for a malformed IPv4 address")
        }
        XCTAssertEqual(field, "localhostIP")
        XCTAssertTrue(captured.isEmpty)
    }

    func testDeleteDomainHandsOffDeleteArgv() {
        var captured: [[String]] = []
        let model = DNSModel(backend: MockBackend(), runPrivilegedInTerminal: { captured.append($0) })

        model.deleteDomain("test")

        XCTAssertEqual(captured, [["system", "dns", "delete", "test"]])
    }
```

- [ ] **Step 2: Run it and confirm it fails.** Command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DNSModelTests`
  Expected FAIL: compile error — `value of type 'DNSModel' has no member 'addDomain'` / `'deleteDomain'`.

- [ ] **Step 3: Implement the handoff + validation.** In `Sources/CapsuleDomain/DNSModel.swift`, insert after the `refresh()` method (and before the class's closing brace):

```swift
    /// Validates the draft and, on success, hands the privileged `system dns create` argv to
    /// the injected Terminal closure (the App layer prefixes `sudo`). Returns the validation
    /// failure otherwise. Never attempts the create in-process — admin is always required.
    @discardableResult
    public func addDomain(_ draft: DNSDraft) -> Result<Void, CapsuleError> {
        switch validatedConfiguration(draft) {
        case let .failure(error):
            return .failure(error)
        case let .success(config):
            runPrivilegedInTerminal(config.arguments)
            onActivity(
                "Requested DNS domain \(config.domain) (requires administrator — opens Terminal).")
            return .success(())
        }
    }

    /// Hands the privileged `system dns delete` argv to the injected Terminal closure.
    public func deleteDomain(_ domain: String) {
        let config = DNSConfiguration(domain: domain)
        runPrivilegedInTerminal(config.deleteArguments)
        onActivity(
            "Requested removal of DNS domain \(domain) (requires administrator — opens Terminal).")
    }

    /// Validates a draft into a `DNSConfiguration`: a non-empty, syntactically valid domain
    /// name and an optional, well-formed IPv4 localhost address.
    func validatedConfiguration(_ draft: DNSDraft) -> Result<DNSConfiguration, CapsuleError> {
        let domain = draft.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty else {
            return .failure(.invalidInput(field: "domain", message: "Enter a domain name."))
        }
        guard Self.isValidDomain(domain) else {
            return .failure(
                .invalidInput(
                    field: "domain",
                    message: "\(domain) is not a valid domain name (e.g. test or app.test)."))
        }
        let ip = draft.localhostIP.trimmingCharacters(in: .whitespacesAndNewlines)
        if ip.isEmpty {
            return .success(DNSConfiguration(domain: domain))
        }
        guard Self.isValidIPv4(ip) else {
            return .failure(
                .invalidInput(
                    field: "localhostIP",
                    message: "\(ip) is not a valid IPv4 address (e.g. 127.0.0.1)."))
        }
        return .success(DNSConfiguration(domain: domain, localhostIP: ip))
    }

    private static func isValidDomain(_ text: String) -> Bool {
        let pattern =
            "^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isValidIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), String(value) == part, (0...255).contains(value) else {
                return false
            }
            return true
        }
    }
```

- [ ] **Step 4: Run it and confirm it passes.** Command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DNSModelTests`
  Expected PASS: all DNSModelTests (refresh + handoff + validation) pass.

- [ ] **Step 5: Commit.**

```bash
make format
git add Sources/CapsuleDomain/DNSModel.swift Tests/CapsuleUnitTests/DNSModelTests.swift
git commit -m "feat(m8): DNSModel create/delete hand off privileged argv to Terminal

addDomain validates the draft (domain name + optional IPv4) then hands
DNSConfiguration.arguments to the injected runPrivilegedInTerminal
closure; deleteDomain hands off .deleteArguments. Neither touches the
backend — admin is always required.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 5.4: `NetworkingView` + `AddDNSDomainSheet` (DNS preferences pane)

Builds the SwiftUI pane that lists DNS domains (distinguishing empty `[]` = "No local DNS domains" from a load failure via `ContentUnavailableView`), an Add Domain… sheet (domain + optional localhost IP, validated, stating "Requires administrator — opens Terminal"), and per-row Delete (confirmation also stating the admin requirement). After a handoff the pane shows "Complete the operation in Terminal, then Refresh." These views mirror `RegistriesView` + `RegistryLoginSheet` exactly. The sheet consumes only Domain primitives — it reads `DNSDraft`, submits via `model.addDomain(_:) -> Result<Void, CapsuleError>`, and renders the returned `ErrorDetail`; it never names a `CapsuleBackend` `*Configuration` type nor calls `.arguments` (arch-guard: `CapsuleUI` imports no `CapsuleBackend`). Behavior is already covered by `DNSModelTests` (the views are thin bindings), so this task is verified by `make build`; the empty-vs-failure rendering is driven by the `DNSLoadState` cases proven in Task 5.2.

**Files:**
- Create: `Sources/CapsuleUI/NetworkingView.swift`
- Create: `Sources/CapsuleUI/AddDNSDomainSheet.swift`

**Interfaces:**
- Consumes: `DNSModel` (`domains`, `loadState`, `notice`, `refresh()`, `addDomain(_:) -> Result<Void, CapsuleError>`, `deleteDomain(_:)`); `DNSDomain`; `DNSDraft`; `DNSLoadState`; `ErrorDetail`; `CapsuleError.detail` (Tasks 5.1–5.3, re-exported via `import CapsuleDomain`). Imports only `CapsuleDomain` + `SwiftUI` — never `CapsuleBackend`.
- Produces: `struct NetworkingView: View` with `init(model: DNSModel)`; `struct AddDNSDomainSheet: View` with `init(onAdd: (DNSDraft) -> ErrorDetail?, onClose: () -> Void)`. Consumed by `PreferencesView` (Task 5.6).

**Steps:**

- [ ] **Step 1: Create the Add Domain sheet.** Create `Sources/CapsuleUI/AddDNSDomainSheet.swift`:

```swift
//
//  AddDNSDomainSheet.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Add a local DNS domain. Collects a domain name and an optional localhost IP, validates
//  them (via the injected model closure), and hands the privileged `system dns create` off to
//  Terminal. The sheet states the administrator requirement up front; it never names a backend
//  Configuration type, never builds argv, and never runs the command in-process.

import CapsuleDomain
import SwiftUI

struct AddDNSDomainSheet: View {
    /// Returns nil on success (handed off to Terminal), or the validation failure to display.
    let onAdd: (DNSDraft) -> ErrorDetail?
    let onClose: () -> Void

    @State private var domain = ""
    @State private var localhostIP = ""
    @State private var failure: ErrorDetail?

    private var trimmedDomain: String {
        domain.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Add DNS Domain", systemImage: "network")
                .font(.headline)

            Form {
                TextField("Domain", text: $domain, prompt: Text("e.g. test"))
                TextField(
                    "Localhost IP (optional)", text: $localhostIP,
                    prompt: Text("e.g. 127.0.0.1"))
            }
            .formStyle(.grouped)

            Label("Requires administrator — opens Terminal.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)

            if let failure {
                VStack(alignment: .leading, spacing: 2) {
                    Label(failure.title, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                    Text(failure.explanation)
                        .font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button("Cancel", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add in Terminal") {
                    let draft = DNSDraft(domain: domain, localhostIP: localhostIP)
                    if let detail = onAdd(draft) {
                        failure = detail
                    } else {
                        onClose()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedDomain.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
```

- [ ] **Step 2: Create the pane.** Create `Sources/CapsuleUI/NetworkingView.swift`:

```swift
//
//  NetworkingView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The Networking preferences pane: lists the configured local DNS domains and adds/removes
//  them. DNS changes always require administrator rights, so Add and Delete hand off to a
//  sudo Terminal session rather than running in-process. Backed by `DNSModel`.

import CapsuleDomain
import SwiftUI

struct NetworkingView: View {
    @Bindable var model: DNSModel

    @State private var showingAdd = false
    @State private var pendingDelete: DNSDomain?
    @State private var handedOff = false

    init(model: DNSModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local DNS Domains")
                .font(.headline)
            Text(
                "Resolve container names under a local domain. Creating or removing a domain "
                    + "requires administrator rights and opens Terminal."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            content

            if handedOff {
                Label(
                    "Complete the operation in Terminal, then Refresh.", systemImage: "terminal"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            if let notice = model.notice {
                Label(notice.detail.explanation, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Domain…", systemImage: "plus")
                }
                Button {
                    handedOff = false
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 320, alignment: .topLeading)
        .task { await model.refresh() }
        .sheet(isPresented: $showingAdd) {
            AddDNSDomainSheet(
                onAdd: { draft in
                    switch model.addDomain(draft) {
                    case .success:
                        handedOff = true
                        return nil
                    case let .failure(error):
                        return error.detail
                    }
                },
                onClose: { showingAdd = false })
        }
        .confirmationDialog(
            "Delete DNS domain \(pendingDelete?.domain ?? "")?",
            isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete in Terminal", role: .destructive) {
                if let domain = pendingDelete {
                    pendingDelete = nil
                    model.deleteDomain(domain.domain)
                    handedOff = true
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Requires administrator — opens Terminal to remove the domain.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity)
        case let .unavailable(detail):
            ContentUnavailableView {
                Label(detail.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(detail.explanation)
            }
        case .loaded:
            if model.domains.isEmpty {
                ContentUnavailableView(
                    "No local DNS domains", systemImage: "network",
                    description: Text("Add a domain to resolve container names locally."))
            } else {
                List {
                    ForEach(model.domains) { domain in
                        HStack {
                            VStack(alignment: .leading) {
                                Label(domain.domain, systemImage: "network")
                                if let ip = domain.localhostIP {
                                    Text("localhost → \(ip)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                pendingDelete = domain
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete \(domain.domain) (requires administrator)")
                        }
                    }
                }
                .frame(minHeight: 160)
            }
        }
    }
}
```

- [ ] **Step 3: Build to verify the views compile.** Command: `make build`
  Expected: build succeeds (the new views are internal and not yet referenced — they wire into `PreferencesView` in Task 5.6).

- [ ] **Step 4: Commit.**

```bash
make format
git add Sources/CapsuleUI/NetworkingView.swift Sources/CapsuleUI/AddDNSDomainSheet.swift
git commit -m "feat(m8): NetworkingView + Add DNS Domain sheet (privileged handoff UI)

Lists DNS domains (empty 'No local DNS domains' vs a load failure), adds
via a validated sheet, and deletes per-row. Add/Delete both state
'Requires administrator — opens Terminal' and show 'Complete the
operation in Terminal, then Refresh.' afterward. Mirrors RegistriesView;
imports only CapsuleDomain + SwiftUI.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 5.5: `AppEnvironment` — privileged Terminal handoff, `DNSModel` wiring, `.grantPermission(.administrator)` safety-net handler

Implements `openPrivilegedCommandInTerminalApp` (the `sudo` variant of M7's `openCommandInTerminalApp`, reusing the private `shellQuote`, prepending the resolved container executable path, and reusing the temp-file sweep), the `runPrivilegedInTerminal` closure, and the `dnsModel` field on the struct/init/`live()`. It also fills in the previously-stubbed `.grantPermission(.administrator)` recovery action **as a guidance-only safety net**: DNS create/delete already perform the privileged handoff *directly* from the per-row Add/Delete buttons in Settings > Networking (`DNSModel` builds the `DNSConfiguration` argv and calls the injected `runPrivilegedInTerminal` closure). `RecoveryAction.grantPermission` carries **no command**, so the handler must NOT attempt to replay a specific argv and there is no "pending command"; it simply appends an activity line pointing the user at Settings > Networking, where the buttons do the privileged work. Consequently `makeActions` keeps its existing signature (no new parameter) — only the `.grantPermission(.administrator)` arm is split out of the `editConfiguration, grantPermission` no-op branch. All `AppEnvironment.swift` edits are additive (insert the field/param/closure/arm; assume earlier phases' M8 model additions are already present).

**Files:**
- Modify: `Sources/CapsuleApp/AppEnvironment.swift` (add struct field after `registriesModel`; add `init` param + assignment; add the `runPrivilegedInTerminal` closure + `dnsModel` in `live()` and thread `dnsModel` into the `AppEnvironment(...)` return; split the `.grantPermission(.administrator)` arm in `makeActions`; add `openPrivilegedCommandInTerminalApp` after `openCommandInTerminalApp`)
- Modify: `Tests/CapsuleUnitTests/AppEnvironmentActionsTests.swift` (append two tests)
- Modify: `Tests/CapsuleUnitTests/CompositionTests.swift` (append one test)

**Interfaces:**
- Consumes: `DNSModel(backend:normalize:onActivity:runPrivilegedInTerminal:)` (Tasks 5.2–5.3); `CLIContainerBackend.executableURL` (`URL`); `ErrorNormalizer.normalize(_:)`; `ShellState.appendActivity(_:)` + `ShellState.activityLog`; `ShellActions(recover:stopServices:)`; `RecoveryAction.grantPermission(PermissionKind)` (+ `.title`); the file-scope private `shellQuote(_:)`.
- Produces: `AppEnvironment.dnsModel: DNSModel` (struct field + `init` param + `live()` value); the file-scope `@MainActor func openPrivilegedCommandInTerminalApp(_ argv: [String], executablePath: String)`; a guidance-only `.grantPermission(.administrator)` recovery arm in `makeActions` (signature unchanged). `dnsModel` consumed by `CapsuleScene` (Task 5.6).

**Steps:**

- [ ] **Step 1: Write the failing tests.** Append to `Tests/CapsuleUnitTests/AppEnvironmentActionsTests.swift` (before the final closing brace on line 25):

```swift
    func testGrantAdministratorAppendsNetworkingGuidance() {
        let shell = ShellState()
        let systemModel = SystemStatusModel(backend: MockBackend())
        let actions = AppEnvironment.makeActions(systemModel: systemModel, shell: shell)

        actions.recover(.grantPermission(.administrator))

        XCTAssertEqual(shell.activityLog.count, 1)
        XCTAssertTrue(
            shell.activityLog[0].contains("Settings > Networking"),
            "the admin safety net points the user at the Networking pane that performs the handoff")
    }

    func testGrantFileAccessStaysInTheNotAvailableBranch() {
        let shell = ShellState()
        let systemModel = SystemStatusModel(backend: MockBackend())
        let actions = AppEnvironment.makeActions(systemModel: systemModel, shell: shell)

        actions.recover(.grantPermission(.fileAccess))

        XCTAssertEqual(shell.activityLog.count, 1)
        XCTAssertTrue(shell.activityLog[0].contains("not available yet"))
        XCTAssertFalse(
            shell.activityLog[0].contains("Networking"),
            "only .administrator gets the Networking guidance; other grants stay no-op")
    }
```

  And append to `Tests/CapsuleUnitTests/CompositionTests.swift` (before the final closing brace):

```swift
    @MainActor
    func testLiveEnvironmentBuildsDNSModel() {
        let environment = AppEnvironment.live()

        XCTAssertEqual(environment.dnsModel.loadState, .idle)
        XCTAssertTrue(environment.dnsModel.domains.isEmpty)
    }
```

- [ ] **Step 2: Run them and confirm they fail.** Command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CompositionTests`
  then
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppEnvironmentActionsTests`
  Expected FAIL: `CompositionTests` fails to compile — `value of type 'AppEnvironment' has no member 'dnsModel'` (which fails the whole test target build). Once `dnsModel` exists, `testGrantAdministratorAppendsNetworkingGuidance` fails at runtime because the admin case currently falls into the no-op branch and appends `Action "Grant Administrator access" is not available yet.` (no `Settings > Networking`). `testGrantFileAccessStaysInTheNotAvailableBranch` is a guard and already holds.

- [ ] **Step 3: Add the struct field.** In `Sources/CapsuleApp/AppEnvironment.swift`, after `public var registriesModel: RegistriesModel` (line 35) add:

```swift
    public var dnsModel: DNSModel
```

- [ ] **Step 4: Add the init parameter + assignment.** In the same `init`, add the parameter after `registriesModel: RegistriesModel,` (line 54):

```swift
        dnsModel: DNSModel,
```

  and the assignment after `self.registriesModel = registriesModel` (line 72):

```swift
        self.dnsModel = dnsModel
```

  (Additive — leave the M8 volume/network model fields/params added by earlier phases in place.)

- [ ] **Step 5: Build the handoff closure + `dnsModel` in `live()`.** In `live()`, immediately after the `openInTerminalApp` closure (after line 129) insert:

```swift
        let runPrivilegedInTerminal: @MainActor ([String]) -> Void = { argv in
            openPrivilegedCommandInTerminalApp(argv, executablePath: cliBackend.executableURL.path)
            shell.appendActivity("Opened in Terminal (sudo): \(argv.joined(separator: " "))")
        }
        let dnsModel = DNSModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            onActivity: { line in shell.appendActivity(line) },
            runPrivilegedInTerminal: runPrivilegedInTerminal
        )
```

  Then thread `dnsModel` into the `return AppEnvironment(...)` call by adding (after `registriesModel: registriesModel,` on line 179, alongside the other M8 models added by earlier phases):

```swift
            dnsModel: dnsModel,
```

  The `let actions = makeActions(systemModel: systemModel, shell: shell)` line (168) is **unchanged** — `makeActions` gains no parameter.

- [ ] **Step 6: Split the `.grantPermission(.administrator)` arm (guidance-only safety net).** In `makeActions`, replace the single no-op arm

```swift
                case .editConfiguration, .grantPermission:
                    shell.appendActivity("Action “\(action.title)” is not available yet.")
```

  with the split:

```swift
                case .grantPermission(.administrator):
                    // SAFETY NET ONLY. DNS create/delete already perform the privileged handoff
                    // directly from the per-row Add/Delete buttons in Settings > Networking
                    // (DNSModel builds the DNSConfiguration argv and calls
                    // runPrivilegedInTerminal). RecoveryAction.grantPermission carries no
                    // command, so we do NOT replay a specific argv here — there is no pending
                    // command. Point the user at the pane that does the privileged work.
                    shell.appendActivity(
                        "Administrator access is required. Open Settings > Networking to add or "
                            + "remove a DNS domain — Capsule opens Terminal with sudo to finish it.")
                case .editConfiguration, .grantPermission:
                    shell.appendActivity("Action “\(action.title)” is not available yet.")
```

  (`makeActions`'s signature stays `makeActions(systemModel:shell:)`.)

- [ ] **Step 7: Add `openPrivilegedCommandInTerminalApp`.** In the same file, immediately after `openCommandInTerminalApp(_:executablePath:)` (after line 247, before the `shellQuote` definition) insert:

```swift
/// The privileged variant of ``openCommandInTerminalApp``: writes a `.command` script whose
/// body is `exec sudo <container-path> <args…>`, so the user authenticates in Terminal and
/// the operation runs with administrator rights. The container executable is given as an
/// absolute path (the external shell has no Capsule context) and every token is shell-quoted.
/// Best-effort — a write/open failure is non-fatal.
@MainActor
func openPrivilegedCommandInTerminalApp(_ argv: [String], executablePath: String) {
    guard !argv.isEmpty else { return }
    let command = ([executablePath] + argv).map(shellQuote).joined(separator: " ")
    let script = "#!/bin/sh\nexec sudo \(command)\n"
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("capsule-\(UUID().uuidString).command")
    do {
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
        // Sweep the throwaway script once Terminal has had time to read it.
        Task {
            try? await Task.sleep(for: .seconds(10))
            try? FileManager.default.removeItem(at: url)
        }
    } catch {
        // Non-fatal: DNS changes can still be run manually in Terminal.
    }
}
```

- [ ] **Step 8: Run the tests and confirm they pass.** Command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppEnvironmentActionsTests`
  then
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CompositionTests`
  Expected PASS: the existing `testRetryInTerminalRoutesToEmbeddedTerminal` still passes (`makeActions` unchanged), both new grant-permission tests pass, and `testLiveEnvironmentBuildsDNSModel` passes.

- [ ] **Step 9: Commit.**

```bash
make format
git add Sources/CapsuleApp/AppEnvironment.swift Tests/CapsuleUnitTests/AppEnvironmentActionsTests.swift Tests/CapsuleUnitTests/CompositionTests.swift
git commit -m "feat(m8): wire DNSModel + privileged sudo Terminal handoff into AppEnvironment

Adds openPrivilegedCommandInTerminalApp (exec sudo <container-path>
<args>, reusing shellQuote + the temp sweep), the runPrivilegedInTerminal
closure, and the live dnsModel. The .grantPermission(.administrator)
recovery arm becomes a guidance-only safety net (no pending command):
DNS create/delete hand off directly from the Networking pane buttons, so
this arm only points the user at Settings > Networking.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

---

### Task 5.6: `PreferencesView` Networking tab + `CapsuleScene` threading

Adds the Networking tab (`Label("Networking", systemImage: "network")` hosting `NetworkingView(model: dnsModel)`) to `PreferencesView`, extends its `init` to accept the `DNSModel`, and threads `environment.dnsModel` through `CapsuleScene` (new `@State` + the `Settings { PreferencesView(...) }` call). Both files are in the additive set, so every edit inserts a field/param/argument/tab; nothing replaces a whole struct or body. Both files are edited together so they compile in lockstep.

**Files:**
- Modify: `Sources/CapsuleUI/PreferencesView.swift` (add `dnsModel` stored property; add the `dnsModel:` init param + assignment; insert the Networking `.tabItem` into the existing `TabView`)
- Modify: `Sources/CapsuleApp/CapsuleScene.swift` (add `@State` field after `registriesModel` ~line 28; add init assignment after the `registriesModel` assignment ~line 51; add the `dnsModel:` argument to the `PreferencesView(...)` call in the `Settings` block ~line 95)

**Interfaces:**
- Consumes: `NetworkingView(model: DNSModel)` (Task 5.4); `AppEnvironment.dnsModel` (Task 5.5); `RegistriesModel` / `RegistriesView` (existing).
- Produces: `PreferencesView.init(registriesModel: RegistriesModel, dnsModel: DNSModel)`; `CapsuleScene` rendering both Registries and Networking tabs. Terminal node — nothing else consumes these.

**Steps:**

- [ ] **Step 1: Add the `dnsModel` stored property to `PreferencesView`.** In `Sources/CapsuleUI/PreferencesView.swift`, after

```swift
    private let registriesModel: RegistriesModel
```

  insert:

```swift
    private let dnsModel: DNSModel
```

- [ ] **Step 2: Extend the `PreferencesView` init (additive — adds the `dnsModel` param + assignment).** Replace

```swift
    public init(registriesModel: RegistriesModel) {
        self.registriesModel = registriesModel
    }
```

  with:

```swift
    public init(registriesModel: RegistriesModel, dnsModel: DNSModel) {
        self.registriesModel = registriesModel
        self.dnsModel = dnsModel
    }
```

- [ ] **Step 3: Insert the Networking tab into the existing `TabView`.** After

```swift
            RegistriesView(model: registriesModel)
                .tabItem { Label("Registries", systemImage: "person.badge.key") }
```

  insert:

```swift
            NetworkingView(model: dnsModel)
                .tabItem { Label("Networking", systemImage: "network") }
```

- [ ] **Step 4: Thread `dnsModel` through `CapsuleScene`.** In `Sources/CapsuleApp/CapsuleScene.swift`, after `@State private var registriesModel: RegistriesModel` (line 28) add:

```swift
    @State private var dnsModel: DNSModel
```

  after `self._registriesModel = State(initialValue: environment.registriesModel)` (line 51) add:

```swift
        self._dnsModel = State(initialValue: environment.dnsModel)
```

  and in the `Settings` block (line 95) replace

```swift
            PreferencesView(registriesModel: registriesModel)
```

  with:

```swift
            PreferencesView(registriesModel: registriesModel, dnsModel: dnsModel)
```

- [ ] **Step 5: Build and run the full suite.** Commands:
  `make build`
  then
  `make test`
  Expected: build succeeds and the full XCTest suite passes (including `DNSModelTests`, `DNSDomainTests`, `AppEnvironmentActionsTests`, `CompositionTests`, and Phase 1's `ErrorNormalizationTests`). The Settings window now shows both the Registries and Networking tabs.

- [ ] **Step 6: Commit.**

```bash
make format
git add Sources/CapsuleUI/PreferencesView.swift Sources/CapsuleApp/CapsuleScene.swift
git commit -m "feat(m8): add Networking (DNS) tab to Preferences and thread dnsModel

PreferencesView gains a Networking tab hosting NetworkingView(model:);
CapsuleScene threads environment.dnsModel through to it (additive edits).
Finishes the spec §7 DNS-in-Settings surface.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

- [ ] **Step 7: Final phase check.** Run the static gates and full CI to confirm the architecture guard (DNS Domain files import only `CapsuleBackend`/`Observation`/`Foundation`; the UI files import only `CapsuleDomain`/`SwiftUI` and name no `CapsuleBackend` Configuration type), license headers, and lint all pass. Command:
  `make ci`
  Expected: build + lint + arch + headers + test all green. (Live GUI smoke — Add opens Terminal with `sudo …/container system dns create <domain>`, Delete with `sudo …/container system dns delete <domain>`, and the list distinguishes empty vs failure — is performed at the milestone close-out per spec §10, not in this phase.)

---


---

## Phase 6: Capability gating, integration tests, close-out

This phase **solely owns capability gating** for Milestone 8 and then hardens, verifies, and closes the milestone out. It adds the single pure gate predicate `SystemHealth.supports(_:)` (Domain), wires that gate into the three places a running-but-unsupported (or service-down) state must withhold the M8 surfaces — the **sidebar** (already feature-gated; this phase locks it with characterization tests), the `.volumes`/`.networks` arms in **`ContentColumnView`**, and the **Networking/DNS pane** in `PreferencesView` — then proves the gating, adds real-CLI integration coverage for `createVolume`/`inspectVolume`/`deleteVolumes`/`pruneVolumes` + the network equivalents + `listDNSDomains` (all §4.1), and closes out with a `make ci`/arch-guard pass, a live GUI smoke checklist, and an adversarial review.

Phases 3, 4, and 5 contain **no** gating logic — they wire only their routing + inspector arms (Phases 3/4 add the `.volumes`/`.networks` arms to `runningContent`; Phase 5 produces `DNSModel`, `NetworkingView`, the Networking tab, and the `dnsModel` threading in `CapsuleScene`). This phase folds in the **complete** gating on top of those surfaces. It **consumes**: `SystemHealth.isRunning`/`availableFeatures`/`SystemFeature` and `SidebarSection.isEnabled(features:)`/`requiredFeature` (§1.8, all existing); the `.volumes`/`.networks` routing arms Phases 3/4 added to `runningContent`; `DNSModel` + `NetworkingView(model:)` + the `PreferencesView(registriesModel:dnsModel:)` init/tab + the `dnsModel` threading in `CapsuleScene` (all Phase 5); and the backend methods `createVolume`/`inspectVolume`/`deleteVolumes`/`pruneVolumes`/`createNetwork`/`inspectNetwork`/`deleteNetworks`/`pruneNetworks`/`listDNSDomains` (§4.1, Phases 1-2). It **produces**: `public func supports(_:) -> Bool` on `SystemHealth` (the single gate predicate), the private `ContentColumnView.isGatedSurfaceUnavailable` + `unsupportedSurface` gate, an additive `systemHealth: SystemHealth` parameter on `PreferencesView.init`, real-CLI integration coverage with an asserted clean skip, and a green `make ci`. It is the terminal phase — no later phase depends on its types.

### Task 6.1: Capability-gate predicate `SystemHealth.supports(_:)` + lock the sidebar gating

**Files:**
- Modify: `Sources/CapsuleDomain/SystemHealth.swift` (add a method immediately after the `availableFeatures` computed property, after line 75)
- Modify: `Tests/CapsuleUnitTests/SystemHealthTests.swift` (add tests before the closing brace of the class)
- Modify: `Tests/CapsuleUnitTests/SidebarSectionTests.swift` (add tests before the closing brace of the class)

**Interfaces:**
- Consumes: `SystemHealth.isRunning: Bool`, `SystemHealth.availableFeatures: Set<SystemFeature>`, `SystemFeature` (all existing, §1.8); `SidebarSection.isEnabled(features:)`, `SidebarSection.requiredFeature` (existing, §1.8).
- Produces: `public func supports(_ feature: SystemFeature) -> Bool` on `SystemHealth` — the single gate predicate consumed by Task 6.3 (DNS pane), and the predicate the Task 6.2 `ContentColumnView` gate is consistent with (`ContentColumnView` calls `SidebarSection.isEnabled`, which `supports` folds the running check into).

- [ ] **Step 1: Write the failing test** for the new predicate in `Tests/CapsuleUnitTests/SystemHealthTests.swift` (insert before the closing brace of the class):
```swift
    func testSupportsRequiresRunningAndFeature() {
        let running = SystemHealth.running(
            version: SystemVersion(client: "1.0.0", server: "1.0.0"),
            features: [.volumes, .networks])
        XCTAssertTrue(running.supports(.volumes))
        XCTAssertTrue(running.supports(.networks))
        // A family the build did not report is unsupported even while running.
        XCTAssertFalse(running.supports(.machines))
    }

    func testSupportsFalseWhenNotRunning() {
        XCTAssertFalse(SystemHealth.stopped.supports(.volumes))
        XCTAssertFalse(SystemHealth.unknown.supports(.networks))
        XCTAssertFalse(SystemHealth.checking.supports(.volumes))
        XCTAssertFalse(
            SystemHealth.unavailable(ErrorDetail(title: "x", explanation: "y")).supports(.networks))
    }
```
- [ ] **Step 2: Run** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SystemHealthTests` → **FAIL** to compile: `value of type 'SystemHealth' has no member 'supports'`.
- [ ] **Step 3: Implement** the predicate in `Sources/CapsuleDomain/SystemHealth.swift`, immediately after the `availableFeatures` computed property (after line 75):
```swift
    /// Whether `feature` is usable right now — the service is running *and* the build
    /// reports the family. Resource surfaces and their Create / Delete / Clean-Up controls
    /// gate on this so an OS or container build that lacks a family disables (rather than
    /// errors on) that UI. Mirrors ``SidebarSection/isEnabled(features:)`` but folds in the
    /// running check, since controls only ever render inside a running service.
    public func supports(_ feature: SystemFeature) -> Bool {
        isRunning && availableFeatures.contains(feature)
    }
```
- [ ] **Step 4: Run** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SystemHealthTests` → **PASS**.
- [ ] **Step 5: Add the sidebar lock tests** in `Tests/CapsuleUnitTests/SidebarSectionTests.swift` (insert before the closing brace of the class) — this is the test the fix packet requires (controls/sidebar disable when the feature set lacks `.volumes`/`.networks`); it characterizes the *existing* `.volumes`/`.networks` gating (§1.8) so it cannot silently regress and so the `ContentColumnView` gate's decision is pinned:
```swift
    func testVolumesAndNetworksSectionsDisabledWithoutFeatures() {
        XCTAssertFalse(SidebarSection.volumes.isEnabled(features: []))
        XCTAssertFalse(SidebarSection.networks.isEnabled(features: []))
    }

    func testVolumesAndNetworksSectionsEnabledWithFeatures() {
        XCTAssertTrue(SidebarSection.volumes.isEnabled(features: [.volumes]))
        XCTAssertTrue(SidebarSection.networks.isEnabled(features: [.networks]))
    }

    func testVolumesAndNetworksRequiredFeatures() {
        XCTAssertEqual(SidebarSection.volumes.requiredFeature, .volumes)
        XCTAssertEqual(SidebarSection.networks.requiredFeature, .networks)
    }
```
- [ ] **Step 6: Run** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SidebarSectionTests` → **PASS** (locks the existing sidebar gating and the decision the `ContentColumnView` gate reuses).
- [ ] **Step 7: Commit**:
```bash
git add Sources/CapsuleDomain/SystemHealth.swift \
        Tests/CapsuleUnitTests/SystemHealthTests.swift \
        Tests/CapsuleUnitTests/SidebarSectionTests.swift
git commit -m "feat(domain): add SystemHealth.supports(_:) capability gate + lock sidebar gating

The pure predicate (running AND family present) is the single gate the volumes/
networks surfaces and the DNS pane disable on. Adds coverage that the .volumes/
.networks sidebar rows disable when the feature is absent — the same predicate the
ContentColumnView gate reuses.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

### Task 6.2: Gate the volumes / networks resource surfaces in `ContentColumnView` (additive)

**Files:**
- Modify: `Sources/CapsuleUI/ContentColumnView.swift` (insert a gate around the `runningContent` dispatch in `body`, lines 34-38; add `isGatedSurfaceUnavailable` + `unsupportedSurface` near line 69)

**Interfaces:**
- Consumes: `SidebarSection.isEnabled(features:)` (§1.8); `SystemHealth.availableFeatures` (§1.8); the `.volumes`/`.networks` routing arms that **Phases 3/4** added to `runningContent`.
- Produces: nothing new exported — a SwiftUI gate (`isGatedSurfaceUnavailable` + `unsupportedSurface`) that withholds the entire `.volumes`/`.networks` resource surface (list + Create… + Delete + Clean Up) when the service is running but this build does not report the section's family. The service-down path is already covered by `healthState`.

**This edit is ADDITIVE relative to Phases 3/4.** Phases 3/4 add the `.volumes`/`.networks` arms to the `runningContent` switch; this task does **not** touch that switch. Instead it inserts the gate around the *dispatch* to `runningContent` inside `body`, scoped to the two M8 surfaces via `isGatedSurfaceUnavailable`. That leaves the `runningContent` switch (and the Phase 3/4 arms in it) completely intact, gates exactly `.volumes`/`.networks` (containers/images/machines keep their own routing), and composes regardless of the exact `VolumeListView(...)`/`NetworkListView(...)` argument lists Phases 3/4 produced. Consistent with the codebase there is no view-body XCTest — the gate's decision is exactly `SidebarSection.isEnabled`, proven by the Task 6.1 `SidebarSectionTests` plus the live smoke (Task 6.6).

- [ ] **Step 1: Insert the gate** around the `runningContent` dispatch in `body` of `Sources/CapsuleUI/ContentColumnView.swift`. This is additive — Phases 3/4 do not edit `body` (they edit only the `runningContent` switch), so this `body` block matches the current source exactly. Replace:
```swift
            } else if health.isRunning {
                runningContent
            } else {
                healthState
            }
```
with:
```swift
            } else if health.isRunning {
                if isGatedSurfaceUnavailable {
                    unsupportedSurface
                } else {
                    runningContent
                }
            } else {
                healthState
            }
```
- [ ] **Step 2: Add** the gate predicate and the unsupported surface to `ContentColumnView` (place both right after `resourcePlaceholder`, before `healthState`):
```swift
    /// True only for a running service whose build does not report the family of a *gated*
    /// resource surface (volumes / networks). Containers / images / machines keep their own
    /// routing untouched — this phase owns capability gating and scopes it to the two M8
    /// surfaces, so the `runningContent` switch (and the arms Phases 3-4 added to it) is left
    /// intact and the gate composes additively around its dispatch.
    private var isGatedSurfaceUnavailable: Bool {
        switch section {
        case .volumes, .networks:
            return !section.isEnabled(features: health.availableFeatures)
        default:
            return false
        }
    }

    /// Shown when the service is running but this build does not report the section's family
    /// (e.g. an OS / container build without `volumes` or `networks`). The whole surface —
    /// list, Create…, Delete, Clean Up — is withheld rather than erroring on use, satisfying
    /// the acceptance rule that unsupported families are hidden, not errored.
    private var unsupportedSurface: some View {
        ContentUnavailableView {
            Label("\(section.title) unavailable", systemImage: "exclamationmark.octagon")
        } description: {
            Text("\(section.title) are not supported by the current container build.")
        }
    }
```
- [ ] **Step 3: Build** `make build` → succeeds (the gate reuses only `CapsuleDomain` symbols already imported by this file; no new imports, so arch-guard stays clean).
- [ ] **Step 4: Run** the gate's backing predicate suite `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SidebarSectionTests` → **PASS** (the decision the gate makes is exactly `SidebarSection.isEnabled`, pinned in Task 6.1).
- [ ] **Step 5: Commit**:
```bash
git add Sources/CapsuleUI/ContentColumnView.swift
git commit -m "feat(ui): gate volumes/networks surfaces on feature availability

Running-but-unsupported families show an explicit 'unavailable' surface instead of
the list, withholding all Create/Delete/Clean Up controls. The gate wraps only the
.volumes/.networks dispatch (additive to the Phase 3/4 runningContent arms — the
switch is untouched); service-down stays on the existing health state.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

### Task 6.3: Gate the Networking / DNS pane on health (additive)

**Files:**
- Modify: `Sources/CapsuleUI/PreferencesView.swift` (add a `systemHealth` stored property + init param + a `.disabled` gate on the Networking tab — additive to the Phase-5 Networking tab)
- Modify: `Sources/CapsuleApp/CapsuleScene.swift` (the `Settings { PreferencesView(...) }` call — add `systemHealth: systemModel.health`)

**Interfaces:**
- Consumes: `SystemHealth.supports(_:)` (Task 6.1); `DNSModel`, `NetworkingView(model:)`, the `PreferencesView(registriesModel:dnsModel:)` init + Networking tab, and the `dnsModel` threading inside `CapsuleScene`'s `Settings` body — **all produced by Phase 5** (Task 5.x, §4.16/§7). `SystemStatusModel.health` via the existing `@State systemModel` in `CapsuleScene`.
- Produces: an additive `systemHealth: SystemHealth` parameter on `PreferencesView.init` and a `.disabled(!systemHealth.supports(.networks))` on the Networking tab — the tab's Add Domain… / per-row Delete / Refresh controls disable as a group when the service is down or the build lacks the networking family. (DNS has no dedicated `BackendFeature`; as a networking sub-surface it shares the `.networks` family gate — §8.)

**This edit is ADDITIVE.** Phase 5 already added the `dnsModel` stored property + init param, the `NetworkingView(model: dnsModel)` Networking tab, and the `dnsModel` argument in `CapsuleScene`'s `Settings` body. This task does **not** rewrite `PreferencesView` and does **not** re-add `dnsModel` (nor any `@State` for it — that threading is Phase 5's). It only inserts the `systemHealth` plumbing and the `.disabled` modifier. The `.disabled(_:)` modifier propagates to every control inside `NetworkingView`, so the gate needs no knowledge of that view's internals. The behavioral proof is the Task 6.1 `supports(_:)` tests plus the live smoke (Task 6.6, DNS-disabled-when-stopped check). `PreferencesView` imports only `CapsuleDomain` + `SwiftUI`; `CapsuleScene` is in `CapsuleApp` (the composition root) — arch-guard stays clean.

- [ ] **Step 1a: Add the `systemHealth` stored property** to `PreferencesView` in `Sources/CapsuleUI/PreferencesView.swift`, immediately after the Phase-5 `dnsModel` property. Insert:
```swift
    private let systemHealth: SystemHealth
```
so the property block reads (Phase-5 `registriesModel`/`dnsModel` already present):
```swift
    private let registriesModel: RegistriesModel
    private let dnsModel: DNSModel
    private let systemHealth: SystemHealth
```
- [ ] **Step 1b: Extend the initializer** (Phase 5 produced `init(registriesModel:dnsModel:)`). Add the `systemHealth` parameter and its assignment so it reads:
```swift
    public init(
        registriesModel: RegistriesModel,
        dnsModel: DNSModel,
        systemHealth: SystemHealth
    ) {
        self.registriesModel = registriesModel
        self.dnsModel = dnsModel
        self.systemHealth = systemHealth
    }
```
- [ ] **Step 1c: Gate the Networking tab.** Phase 5's body has `NetworkingView(model: dnsModel)` carrying a `.tabItem { Label("Networking", systemImage: "network") }`. Add the `.disabled` modifier to that view so the tab reads:
```swift
            NetworkingView(model: dnsModel)
                .disabled(!systemHealth.supports(.networks))
                .tabItem { Label("Networking", systemImage: "network") }
```
- [ ] **Step 2: Add the `systemHealth` argument** in the `Settings` scene of `Sources/CapsuleApp/CapsuleScene.swift`. Phase 5 produced the `dnsModel:` argument; this is purely additive — do **not** re-declare or re-thread `dnsModel`. Replace:
```swift
        Settings {
            PreferencesView(
                registriesModel: registriesModel,
                dnsModel: dnsModel)
        }
```
with:
```swift
        Settings {
            PreferencesView(
                registriesModel: registriesModel,
                dnsModel: dnsModel,
                systemHealth: systemModel.health)
        }
```
- [ ] **Step 3: Build** `make build` → succeeds. (`PreferencesView` imports only `CapsuleDomain` + `SwiftUI`; `CapsuleScene` is the composition root — arch-guard stays clean.)
- [ ] **Step 4: Run** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SystemHealthTests` → **PASS** (the gate's predicate, `supports(.networks)`, is covered there).
- [ ] **Step 5: Commit**:
```bash
git add Sources/CapsuleUI/PreferencesView.swift Sources/CapsuleApp/CapsuleScene.swift
git commit -m "feat(ui): health-gate the Networking/DNS preferences pane

The DNS pane's Add/Delete/Refresh controls disable as a group when the service is
down or the build lacks the networking family, so DNS mutation never looks available
when it cannot work. Additively threads SystemHealth from CapsuleScene into the
Phase-5 PreferencesView (dnsModel + the Networking tab stay Phase 5's).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

### Task 6.4: Real-CLI integration tests (volumes, networks, DNS list) + asserted clean skip

**Files:**
- Modify: `Tests/CapsuleIntegrationTests/CLIBackendIntegrationTests.swift` (full file — refactor the skip into a per-test gate, add an always-running skip-guard assertion, add volume/network lifecycle + DNS-list tests)

**Interfaces:**
- Consumes (all §4.1, from Phases 1-2): `CLIContainerBackend()`; `createVolume(_:)`, `listVolumes()`, `inspectVolume(names:) -> Parsed<[VolumeSummary]>`, `deleteVolumes(names:)`, `pruneVolumes() -> PruneResult`; `createNetwork(_:)`, `listNetworks()`, `inspectNetwork(names:) -> Parsed<[NetworkSummary]>`, `deleteNetworks(names:)`, `pruneNetworks() -> PruneResult`; `listDNSDomains() -> [DNSDomainSummary]`; `VolumeConfiguration(name:)`, `NetworkConfiguration(name:)` (§4.2 — name-only is valid; the CLI auto-assigns a network subnet, so the test never collides with `default`).
- Produces: integration coverage that self-skips unless `CAPSULE_INTEGRATION=1`, plus `testGuardSkipsCleanlyWithoutEnv` which runs unconditionally and asserts the skip semantics (so a CI run with the flag unset is a clean skip, never a failure or an accidental CLI hit).

- [ ] **Step 1: Write the failing test** by replacing the entire contents of `Tests/CapsuleIntegrationTests/CLIBackendIntegrationTests.swift`:
```swift
//
//  CLIBackendIntegrationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Integration tests exercise the real `container` CLI and therefore require an
//  Apple-silicon macOS host with the CLI installed. The CLI-touching tests self-skip
//  unless CAPSULE_INTEGRATION=1, so they stay green (skipped) in CI. `requireIntegration()`
//  is the single skip gate; `testGuardSkipsCleanlyWithoutEnv` runs unconditionally and
//  asserts that gate, so a flag-unset run is a clean skip rather than a failure.

import CapsuleBackend
import XCTest

@testable import CapsuleCLIBackend

final class CLIBackendIntegrationTests: XCTestCase {
    private var integrationEnabled: Bool {
        ProcessInfo.processInfo.environment["CAPSULE_INTEGRATION"] == "1"
    }

    /// The single skip gate for every CLI-touching test.
    private func requireIntegration() throws {
        try XCTSkipUnless(
            integrationEnabled,
            "Set CAPSULE_INTEGRATION=1 to run integration tests (requires the container CLI)."
        )
    }

    // MARK: - Skip guard (always runs; never touches the CLI)

    func testGuardSkipsCleanlyWithoutEnv() throws {
        if integrationEnabled {
            XCTAssertEqual(ProcessInfo.processInfo.environment["CAPSULE_INTEGRATION"], "1")
        } else {
            // Flag unset => the CLI-touching tests skip rather than run or fail.
            XCTAssertNotEqual(ProcessInfo.processInfo.environment["CAPSULE_INTEGRATION"], "1")
        }
    }

    // MARK: - Existing smoke

    func testVersionReturnsClientString() async throws {
        try requireIntegration()
        let backend = CLIContainerBackend()
        let version = try await backend.version()
        XCTAssertFalse(version.client.isEmpty)
    }

    func testListContainersSucceeds() async throws {
        try requireIntegration()
        let backend = CLIContainerBackend()
        _ = try await backend.listContainers()
    }

    // MARK: - M8: volume lifecycle (create / list / inspect / delete / prune)

    func testVolumeLifecycleAgainstRealCLI() async throws {
        try requireIntegration()
        let backend = CLIContainerBackend()
        let name = "capsule-it-vol-\(UUID().uuidString.prefix(8))"

        do {
            try await backend.createVolume(VolumeConfiguration(name: name))

            let listed = try await backend.listVolumes()
            XCTAssertTrue(
                listed.contains { $0.name == name }, "created volume should appear in the list")

            let inspected = try await backend.inspectVolume(names: [name])
            XCTAssertFalse(inspected.raw.isEmpty, "inspect should return raw JSON")
            XCTAssertEqual(inspected.value?.first?.name, name)

            try await backend.deleteVolumes(names: [name])
            let afterDelete = try await backend.listVolumes()
            XCTAssertFalse(
                afterDelete.contains { $0.name == name }, "deleted volume should be gone")

            _ = try await backend.pruneVolumes()
        } catch {
            // Best-effort cleanup so a mid-test failure never leaks the throwaway volume.
            try? await backend.deleteVolumes(names: [name])
            throw error
        }
    }

    // MARK: - M8: network lifecycle (create / list / inspect / delete / prune)

    func testNetworkLifecycleAgainstRealCLI() async throws {
        try requireIntegration()
        let backend = CLIContainerBackend()
        let name = "capsule-it-net-\(UUID().uuidString.prefix(8))"

        do {
            // No subnet: let the CLI auto-assign so the test never collides with `default`.
            try await backend.createNetwork(NetworkConfiguration(name: name))

            let listed = try await backend.listNetworks()
            XCTAssertTrue(
                listed.contains { $0.name == name }, "created network should appear in the list")

            let inspected = try await backend.inspectNetwork(names: [name])
            XCTAssertFalse(inspected.raw.isEmpty, "inspect should return raw JSON")
            XCTAssertEqual(inspected.value?.first?.name, name)

            try await backend.deleteNetworks(names: [name])
            let afterDelete = try await backend.listNetworks()
            XCTAssertFalse(
                afterDelete.contains { $0.name == name }, "deleted network should be gone")

            _ = try await backend.pruneNetworks()
        } catch {
            try? await backend.deleteNetworks(names: [name])
            throw error
        }
    }

    // MARK: - M8: DNS list (unprivileged — must succeed, empty or populated)

    func testListDNSDomainsAgainstRealCLI() async throws {
        try requireIntegration()
        let backend = CLIContainerBackend()
        // Unprivileged list: an empty `[]` is success, not failure; it must never throw.
        _ = try await backend.listDNSDomains()
    }
}
```
- [ ] **Step 2: Run (flag unset, like CI)** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CLIBackendIntegrationTests`. Expected: `testGuardSkipsCleanlyWithoutEnv` runs and **PASSES**; the five CLI-touching tests report **skipped** ("Set CAPSULE_INTEGRATION=1 …"). If `createVolume`/`inspectVolume`/… are not yet present from Phases 1-2 the build **FAILS** to compile — confirming the contract dependency. This is the expected first state until Phases 1-2 land.
- [ ] **Step 3: Run (flag set, on the real host)** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CAPSULE_INTEGRATION=1 swift test --filter CLIBackendIntegrationTests` → all tests **PASS** against the live `container` CLI (the throwaway volume/network are created and removed; DNS list returns without throwing).
- [ ] **Step 4: Commit**:
```bash
git add Tests/CapsuleIntegrationTests/CLIBackendIntegrationTests.swift
git commit -m "test(integration): real-CLI volume/network lifecycle + DNS list (CAPSULE_INTEGRATION)

Creates/lists/inspects/deletes/prunes a throwaway volume and network against the real
container CLI and lists DNS unprivileged. requireIntegration() is the single skip gate;
testGuardSkipsCleanlyWithoutEnv asserts a flag-unset run skips cleanly (no CLI hit).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

### Task 6.5: Full `make ci` + arch-guard verification

**Files:**
- No new source. Runs the gates over the whole M8 diff and folds in any formatting fixups.

**Interfaces:**
- Consumes: every M8 file from Phases 1-5 plus Tasks 6.1-6.4.
- Produces: a green `make ci` (build + lint + arch + headers + test) and a clean arch-guard, gating close-out.

- [ ] **Step 1: Arch-guard** — `make arch` → **PASS**. Confirm specifically: `SystemHealth.supports(_:)` is pure (`CapsuleDomain` uses no `Foundation.Process`, no UI import); `ContentColumnView`/`PreferencesView` reference only `CapsuleDomain` types (no `import CapsuleBackend`/`CapsuleCLIBackend`); `CapsuleScene` (in `CapsuleApp`, the composition root) is the only place threading `dnsModel`/`systemModel.health` into `PreferencesView`. Equivalently run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ArchitectureGuardTests` → **PASS**.
- [ ] **Step 2: Format + lint** — `make format` then `make lint` → clean (no diff). The license-header check passes on every file touched (no new files in this phase; all modified files keep their existing headers).
- [ ] **Step 3: Headers** — `make headers` → **PASS**.
- [ ] **Step 4: Full CI** — `make ci` (build + lint + arch + headers + test) → all green. The integration tests report **skipped** (flag unset), confirming the Task 6.4 clean-skip path under the exact CI invocation.
- [ ] **Step 5: Commit** any formatting fixups (only if `make format` produced a diff):
```bash
git add -A
git commit -m "chore: swift-format M8 close-out

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he"
```

### Task 6.6: Live GUI smoke + adversarial review + milestone close-out

**Files:**
- No source. Manual GUI smoke, an adversarial code review of the M8 diff, milestone-memory update, branch push, and PR preparation. Mirrors the M5.5/M6/M7 close-out tradition.

**Interfaces:**
- Consumes: the full M8 feature set (Volumes/Networks browsers + inspectors + Create/Prune sheets, DNS pane, the gating from Tasks 6.1-6.3) on a live host with the `container` service running.
- Produces: a verified, reviewed, pushed `milestone-8-volumes-networks-dns` branch + PR body; updated auto-memory.

- [ ] **Step 1: Launch** the app (`make run`, or open the built bundle) with the container service **running**.
- [ ] **Step 2: Live GUI smoke checklist** — walk every acceptance path (§11), confirming each:
  - **Volumes — create:** open `.volumes`, **Create…** with a unique name; expand **Advanced Options** and set a Size (e.g. `64M`) + one `--opt` row + one `--label` row; confirm the **live command preview** reads `volume create --label … --opt … -s 64M <name>`; create → the row appears (list reloads, no Activity task).
  - **Volumes — inspect:** select the new volume → **Summary** tab shows source/size/labels and the attached-container count; **Raw JSON** tab is copyable.
  - **Volumes — delete:** context-menu **Delete…** on the new volume → a **confirmation sheet** with the data-loss warning ("Deleting <name> permanently destroys its data.") → confirm → it disappears.
  - **Volumes — prune:** toolbar **Clean Up** → the **preview sheet** lists zero-attachment candidates with the "best-effort; runtime decides the final set" note → run → the honest reclaimed result is shown.
  - **Networks — create / inspect / delete / prune:** same loop. On Create, type a subnet that overlaps `default` (`192.168.64.0/24`) and confirm the **inline conflict message** names `default` and **disables Create**; clear it (empty subnet) and create; inspect shows mode/plugin/subnet/gateway/ipv6; the **`default` (builtin) network** shows a lock affordance with **Delete disabled** and is **excluded** from the prune preview/bulk.
  - **DNS (Settings › Networking):** the list distinguishes **empty `[]` → "No local DNS domains"** from a **load failure**. **Add Domain…** states *"Requires administrator — opens Terminal"* and, on submit, opens **Terminal** running exactly `sudo <resolved-container-path> system dns create <domain>` (with `--localhost <ip>` when set). Per-row **Delete** opens Terminal with `sudo … system dns delete <domain>`. After handoff the pane shows "Complete the operation in Terminal, then Refresh"; **Refresh** re-lists. Nothing fails silently.
  - **Gating — service down:** **Stop** the service from the System pane. Confirm the `.volumes`/`.networks` sections route to the **health state** (not an empty list), and the **Networking** preferences pane's Add/Delete/Refresh controls are **disabled** (the `.disabled(!systemHealth.supports(.networks))` gate). Restart and confirm they re-enable. (The unsupported-family path — `ContentColumnView.unsupportedSurface` via `isGatedSurfaceUnavailable` — cannot be exercised on this build since all three families are reported; record that it is verified by the `SystemHealth.supports`/`SidebarSection.isEnabled` unit tests, which are the acceptance evidence for hidden/disabled-when-unsupported.)
- [ ] **Step 3: Adversarial review** — invoke the **superpowers:requesting-code-review** skill (a fresh-eyes pass over the full M8 diff `git diff main...milestone-8-volumes-networks-dns`). Focus the reviewer on: argv edge cases (`-s` size suffix, repeated `--opt`/`--option`/`--label`, omitted optionals, `--subnet-v6`); the `(try sudo?)` → `permissionRequired(.administrator)` normalization and the `sudo` handoff (`shellQuote`, resolved container path, temp `.command` sweep — no secret/arg injection); subnet-conflict false negatives/positives across IPv4+IPv6 and malformed input; attachment-index staleness vs. prune-preview honesty; builtin-network protection (no delete, excluded from bulk/prune); and the gating owned by this phase (no surface or DNS control reachable while down/unsupported — `ContentColumnView.isGatedSurfaceUnavailable` scoped to volumes/networks, the `PreferencesView` `.disabled` gate, and the `SystemHealth.supports`/`SidebarSection.isEnabled` predicates). Triage findings with **superpowers:receiving-code-review**; fix any **Critical/High** and commit each fix with the two required trailer lines.
- [ ] **Step 4: Update milestone memory** — record the M8 outcome (volumes/networks browsers + inspectors + create/delete/prune, DNS sudo Terminal handoff, capability gating, test count, smoke + adversarial results, branch, PR/merge status) following the established `capsule-milestoneN-done.md` format and link it from `MEMORY.md`.
- [ ] **Step 5: Push + PR** — push `milestone-8-volumes-networks-dns`; create the PR with `gh` (if `gh` is unavailable, save the PR body to the scratchpad and emit the compare URL). PR body ends with:
```
🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he
```
- [ ] **Step 6: Final gate** — re-run `make ci` on the tip of the branch → all green (integration skipped); confirm the working tree is clean (`git status`). Milestone 8 is closed out.


---


---

## Appendix A — Shared Contract Reference

The canonical type/method names and the exact license header, captured from the current source. Tasks above use these names; consult this when a task references a type defined in another phase.

**Post-review reconciliations (binding; supersede the literal sketches below where they differ):**
- The internal `CLIVolumeRecord` uses the nested `{configuration{…}, id}` shape pinned by `volume-ls.json`; `CLIDNSRecord`'s primary key is `domainName`. These supersede the flat sketches in §4.4 (cross-phase surfaces `VolumeSummary`/`parseVolumes`/`DNSDomainSummary` are unchanged).
- `MockBackend` gains mutation recorders (`lastCreatedVolume`, `lastDeletedVolumeNames`, `didPruneVolumes`, `lastCreatedNetwork`, `lastDeletedNetworkNames`, `didPruneNetworks`) per Phase 1.
- The container-attachment surfacing (`CLIContainerRecord` mounts/networks, `parseContainers`, `ContainerSummary`/`Container` `volumeMounts`/`networkNames`) is owned by Phase 2, not Phase 1.

# Milestone 8 — Shared Contract Reference (Volumes, Networks & DNS)

This document is the **single source of truth** for the six parallel M8 phase-authors. Every signature here reflects the *exact current code* (captured by reading the files) or a *canonical new shape* you MUST use verbatim so the phases compose. Where the design spec was ambiguous or internally inconsistent, the resolution is called out under **CONTRACT DECISION** — treat those as binding.

Branch: `milestone-8-volumes-networks-dns`. Framework: **XCTest**. Language mode: Swift v5 (tools 6.0).

---

## 1. EXACT current signatures (as they exist today)

### 1.1 `ContainerBackend` protocol — `Sources/CapsuleBackend/ContainerBackend.swift`

```swift
public protocol ContainerBackend: Sendable {
    // System & capabilities
    func version() async throws -> BackendVersion
    func capabilities() async throws -> BackendCapabilities
    func systemStatus() async throws -> SystemRunState
    func startSystem() async throws
    func stopSystem() async throws

    // Containers
    func listContainers(all: Bool) async throws -> [ContainerSummary]
    func inspectContainer(id: String) async throws -> Parsed<ContainerSummary>
    func startContainer(id: String) async throws
    func stopContainer(id: String, options: StopOptions) async throws
    func removeContainer(id: String, force: Bool) async throws
    func killContainer(id: String, signal: String?) async throws
    func pruneContainers() async throws -> PruneResult
    func exportContainer(id: String, to url: URL) async throws
    func containerStats(ids: [String]) async throws -> [ContainerStatsSample]
    func streamContainerStats(ids: [String], interval: Duration)
        -> AsyncThrowingStream<[ContainerStatsSample], Error>
    func followLogs(container id: String) -> AsyncThrowingStream<OutputLine, Error>
    func fetchLogs(container id: String, tail: Int?, boot: Bool) async throws -> [OutputLine]
    func runContainer(_ config: RunConfiguration) async throws -> String
    func copyToContainer(source: URL, containerID: String, containerPath: String) async throws
    func copyFromContainer(containerID: String, containerPath: String, destination: URL) async throws
    func listContainerDirectory(id: String, path: String) async throws -> [ContainerFileEntry]

    // Images
    func listImages() async throws -> [ImageSummary]
    func inspectImage(reference: String) async throws -> Parsed<ImageSummary>
    func removeImage(reference: String) async throws
    func pullImage(reference: String, platform: String?) -> AsyncThrowingStream<OutputLine, Error>
    func pushImage(reference: String, platform: String?) -> AsyncThrowingStream<OutputLine, Error>
    func saveImage(references: [String], to url: URL, platform: String?) async throws
    func loadImage(from url: URL) async throws
    func tagImage(source: String, target: String) async throws
    func pruneImages(all: Bool) async throws -> PruneResult
    func buildImage(_ config: BuildConfiguration) -> AsyncThrowingStream<OutputLine, Error>

    // Volumes / networks / registries / machines / builder
    func listVolumes() async throws -> [VolumeSummary]
    func listNetworks() async throws -> [NetworkSummary]
    func listRegistries() async throws -> [RegistrySummary]
    func listMachines() async throws -> [MachineSummary]
    func builderStatus() async throws -> BuilderStatus
    func registryLogin(server: String, username: String?, password: String?) async throws
    func registryLogout(server: String) async throws
    func registryTest(server: String, username: String?, password: String?) async throws

    // Escape hatches
    func runRaw(_ arguments: [String]) async throws -> RawCommandOutput
    func streamRaw(_ arguments: [String]) -> AsyncThrowingStream<OutputLine, Error>
}
```

Protocol extension convenience methods (default impls): `listContainers()` → `listContainers(all: false)`; `stopContainer(id:)` → `.default`; `pullImage(reference:)` → `platform: nil`.

> **Every new M8 backend method (§4) must be added BOTH to this protocol AND to `MockBackend` AND to `CLIContainerBackend`** or the build breaks (no protocol extension default planned).

### 1.2 `Parsed<T>` & current value types — `Sources/CapsuleBackend/BackendResourceTypes.swift`

```swift
public struct Parsed<Value: Sendable>: Sendable {
    public var value: Value?
    public var raw: String
    public init(value: Value?, raw: String)
}

public struct VolumeSummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String { name }
    public var name: String
    public var source: String?
    public init(name: String, source: String? = nil)
}

public struct NetworkSummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var name: String
    public var mode: String?
    public var gateway: String?
    public var subnet: String?
    public init(id: String, name: String, mode: String? = nil,
                gateway: String? = nil, subnet: String? = nil)
}

public struct RegistrySummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String { server }
    public var server: String
    public init(server: String)
}

public struct RawCommandOutput: Sendable, Equatable, Codable { /* exitCode, stdout, stderr */ }
```

`ContainerSummary` (in `BackendValueTypes.swift`) today: `id, name, image, state, ip?, createdAt?` with `init(id:name:image:state:ip:createdAt:)`. `BackendError` (same file): `.notImplemented(String)`, `.executableNotFound(String)`, `.nonZeroExit(command: String, code: Int32, stderr: String)`, `.decodingFailed(String)`.

### 1.3 Wire models (current) — `Sources/CapsuleCLIBackend/WireModels.swift`

```swift
struct CLINetworkRecord: Decodable {
    let id: String
    let configuration: Configuration
    let status: Status?
    struct Configuration: Decodable {
        let name: String
        let mode: String?
    }
    struct Status: Decodable {
        let ipv4Gateway: String?
        let ipv4Subnet: String?
    }
}

struct CLIVolumeRecord: Decodable {            // currently only:
    let name: String?
    let source: String?
}

struct CLIContainerRecord: Decodable {         // the attachment cross-reference source
    let id: String
    let configuration: Configuration
    let status: Status
    struct Configuration: Decodable {
        let id: String
        let image: ImageDescription
        let creationDate: String?
        struct ImageDescription: Decodable { let reference: String }
        // NOTE: configuration.mounts and configuration.networks are NOT decoded today.
    }
    struct Status: Decodable {
        let state: String
        let networks: [Attachment]             // runtime attachments (ipv4Address) — NOT names
        struct Attachment: Decodable {
            let ipv4Address: String?
            let address: String?
            var ipAddress: String? { /* strips /CIDR */ }
        }
    }
}
```

`network-ls.json` real fixture (already committed) confirms the populated shape:
```json
[{"configuration":{"creationDate":"2026-06-27T12:15:24Z","labels":{"com.apple.container.resource.role":"builtin"},"mode":"nat","name":"default","options":{},"plugin":"container-network-vmnet"},"id":"default","status":{"ipv4Gateway":"192.168.64.1","ipv4Subnet":"192.168.64.0/24","ipv6Subnet":"fdb6:5eb:8ee:85cf::/64"}}]
```

### 1.4 `RunConfiguration` / `BuildConfiguration` (full) — `Sources/CapsuleBackend/`

```swift
public struct RunConfiguration: Sendable, Equatable {
    public var image: String
    public var command: [String]
    public var env: [String]
    public var publishPorts: [String]
    public var volumes: [String]
    public var name: String?
    public var workdir: String?
    public var user: String?
    public var interactive: Bool
    public var tty: Bool
    public var detach: Bool
    public var remove: Bool
    public init(image:name:command:env:publishPorts:volumes:workdir:user:
                interactive:tty:detach:remove:)   // all but image have defaults
    public var arguments: [String] {
        var argv = ["run"]
        if detach { argv.append("-d") }
        if interactive { argv.append("-i") }
        if tty { argv.append("-t") }
        if remove { argv.append("--rm") }
        if let name { argv += ["--name", name] }
        for value in env { argv += ["-e", value] }
        for port in publishPorts { argv += ["-p", port] }
        for volume in volumes { argv += ["-v", volume] }
        if let workdir { argv += ["-w", workdir] }
        if let user { argv += ["-u", user] }
        argv.append(image)
        argv += command
        return argv
    }
}

public struct BuildConfiguration: Sendable, Equatable {
    public var contextDirectory: URL
    public var tag: String
    public var dockerfile: String?
    public var buildArgs: [String]
    public var noCache: Bool
    public var plainProgress: Bool
    public init(contextDirectory:tag:dockerfile:buildArgs:noCache:plainProgress:)
    public var arguments: [String] {
        var argv = ["build", "--tag", tag]
        if let dockerfile { argv += ["--file", dockerfile] }
        for value in buildArgs { argv += ["--build-arg", value] }
        if noCache { argv.append("--no-cache") }
        if plainProgress { argv += ["--progress", "plain"] }
        argv.append(contextDirectory.path)
        return argv
    }
}
```

> **Pattern to copy for `*Configuration`:** `public struct`, `Sendable, Equatable`, all-defaulted init except required fields, a single computed `var arguments: [String]` that *appends flags first then positional last*. These types live in `CapsuleBackend` (Domain may construct them; arch-guard permits `CapsuleDomain → CapsuleBackend`).

### 1.5 `ArgumentBuilder` fluent API — `Sources/CapsuleCLIBackend/ArgumentBuilder.swift`

```swift
public struct ArgumentBuilder: Sendable, Equatable {
    public private(set) var arguments: [String]
    public init(_ subcommand: String...)                    // seeds arguments = subcommand
    public func adding(_ args: String...) -> ArgumentBuilder // append positionals
    public func adding(contentsOf values: [String]) -> ArgumentBuilder
    public func flag(_ name: String, _ value: String?) -> ArgumentBuilder   // appends [name,value] iff value != nil
    public func option(_ name: String, enabled: Bool) -> ArgumentBuilder     // appends [name] iff enabled
}
```
`.arguments` is the produced argv. All methods are value-returning (chainable). The CLI executable token is **never** included (the runner owns `executableURL`).

### 1.6 Errors — `CapsuleError`, `PermissionKind`, `RecoveryAction`, `ErrorDetail`

`Sources/CapsuleDomain/CapsuleError.swift`:
```swift
public enum PermissionKind: String, Sendable, Equatable, Hashable, Codable {
    case administrator   // title: "Administrator access"
    case fileAccess      // title: "File access"
    case network         // title: "Network access"
    public var title: String { ... }
}

public enum RecoveryAction: Sendable, Equatable, Hashable {
    case retry
    case retryInTerminal(command: [String])
    case startServices
    case openLogs
    case editConfiguration
    case exportDiagnostics
    case grantPermission(PermissionKind)
    public var title: String { ... }   // grantPermission -> "Grant \(kind.title)"
}

public enum CapsuleError: Error, Sendable, Equatable {
    case daemonUnavailable(message: String, recovery: [RecoveryAction])
    case commandFailed(command: [String], exitCode: Int32?, stderr: String)
    case interrupted(signal: Int32)
    case invalidInput(field: String, message: String)
    case permissionRequired(kind: PermissionKind, message: String)
    case unsupportedFeature(message: String)
    case unknown(message: String)
}
```

`Sources/CapsuleDomain/ErrorDetail.swift`:
```swift
public struct ErrorDetail: Sendable, Equatable {
    public var title: String
    public var explanation: String
    public var recoveryActions: [RecoveryAction]
    public init(title: String, explanation: String, recoveryActions: [RecoveryAction] = [])
    public var diagnosticInfo: DiagnosticInfo { DiagnosticInfo(summary: title, detail: explanation) }
}

extension CapsuleError {
    public var detail: ErrorDetail { ... }   // permissionRequired -> title "\(kind.title) required",
                                             // recoveryActions [.grantPermission(kind), .openLogs]
    public var status: OperationStatus { ... } // permissionRequired -> .failedBeforeExecution
}
```
> **Note the existing `.permissionRequired` detail title is `"\(kind.title) required"` → `"Administrator access required"`.** The spec §7 wording matches this; do not invent a new title.

### 1.7 `ErrorNormalizer` — `Sources/CapsuleDiagnostics/ErrorNormalization.swift`

```swift
public enum ErrorNormalizer {
    public static func normalize(_ error: Error) -> CapsuleError
    public static func detail(for error: Error) -> ErrorDetail        // = normalize(error).detail
    public static func diagnosticInfo(for error: Error) -> DiagnosticInfo
}
```
Entry point `normalize(_:)`: a `CapsuleError` passes through unchanged; a `BackendError` goes to `normalizeBackendError`; anything else → `.unknown`. `normalizeBackendError` matches **daemon signatures** against `stderr` *and* `command` via `hasDaemonSignature` (lowercased `contains`) over:
```swift
["connection refused","could not connect","failed to connect","not running",
 "xpc","launchd","apiserver","no such file or directory"]
```
A match → `.daemonUnavailable(...)`; otherwise `.nonZeroExit` → `.commandFailed(command: command.split(separator:" ").map(String.init), exitCode: code, stderr: stderr)`. `.decodingFailed` → `.unknown`; `.notImplemented` → `.unsupportedFeature`.

> **M8 (§7) adds an administrator-signature check BEFORE the daemon check**, matching `"try sudo?"` and `"must run as an administrator"` (lowercased) → `.permissionRequired(kind: .administrator, message: <trimmed stderr or default>)`. Pattern this exactly like `daemonSignatures` (a private static array + a `hasAdministratorSignature` helper, evaluated inside the `.nonZeroExit` case ahead of `hasDaemonSignature`).

### 1.8 Capabilities & nav — `SystemFeature`, `SidebarSection`

`Sources/CapsuleDomain/SystemHealth.swift`:
```swift
public enum SystemFeature: String, Sendable, CaseIterable, Codable {
    case system, containers, images, volumes, networks, registries, machines, builder, logsFollow
}
```
Mirror of `BackendFeature` (same raw values; `BackendFeature` in `Sources/CapsuleBackend/BackendCapabilities.swift` has identical cases). `SystemHealth.availableFeatures: Set<SystemFeature>`; `.running(version:features:)` carries them.

`Sources/CapsuleUI/SidebarSection.swift`:
```swift
public enum SidebarSection: String, CaseIterable, Identifiable, Sendable {
    case containers, images, volumes, networks, machines, system
    public var id: String { rawValue }
    public var title: String { ... }            // volumes -> "Volumes", networks -> "Networks"
    public var symbolName: String { ... }        // volumes -> "externaldrive", networks -> "network"
    public var requiredFeature: SystemFeature? { // volumes -> .volumes, networks -> .networks, system -> nil
        ... }
    public func isEnabled(features: Set<SystemFeature>) -> Bool
}
```
> **`.volumes` and `.networks` sidebar rows already exist and already gate on `.volumes`/`.networks`.** M8 does not add sidebar cases; it wires `ContentColumnView` routing + inspectors + models.

---

## 2. EXACT test-harness API

### 2.1 `StubProcessRunner` — `Tests/CapsuleUnitTests/StubProcessRunner.swift`

`final class StubProcessRunner: ProcessRunning, @unchecked Sendable` (uses `@testable import CapsuleCLIBackend`). Properties / behavior:

| Member | Type | Meaning |
|---|---|---|
| `result` | `CommandResult` (var) | Canned result for `run` (default `exitCode:0,stdout:"",stderr:""`). |
| `resultProvider` | `(@Sendable ([String]) -> CommandResult)?` | Per-argv override; when set its return wins over `result`. |
| `streamLines` | `[OutputLine]` (var) | Lines yielded by `stream`. |
| `streamExit` | `Int32` (var, default 0) | 0 → stream finishes; non-zero → finishes throwing `BackendError.nonZeroExit(command:argv.joined, code:streamExit, stderr:"")`. |
| `lastCall` | `[String]?` (computed) | The most recent argv (`calls.last`). |
| `lastStandardInput` | `String?` (private(set)) | stdin of the most recent `run` (proves secrets go off-argv). |

`run(_:environment:standardInput:)` appends argv to `calls`, records `standardInput`, returns `resultProvider?(argv) ?? result`. `stream(_:environment:)` appends argv, yields `streamLines`, then finishes per `streamExit`. There is a convenience `ProcessRunning.run(_:environment:)` (stdin `nil`).

### 2.2 `CLIContainerBackendTests` — backend over the stub

`makeBackend` helper (use it verbatim for all new backend tests):
```swift
private func makeBackend(_ runner: StubProcessRunner) -> CLIContainerBackend {
    CLIContainerBackend(
        executableURL: URL(fileURLWithPath: "/usr/local/bin/container"),
        runner: runner)            // the internal testing init (CapsuleCLIBackend is @testable)
}
```
Canonical assertion idiom:
```swift
let stub = StubProcessRunner()
stub.result = CommandResult(exitCode: 0, stdout: Fixture.text("network-ls"), stderr: "")
let rows = try await makeBackend(stub).listNetworks()
XCTAssertEqual(stub.lastCall, ["network", "list", "--format", "json"])
```
Error mapping is asserted by catching `BackendError.nonZeroExit(command, code, stderr)`. For M8's admin-signature mapping, drive `ErrorNormalizer.normalize(...)` (or the backend method, then normalize) and assert the resulting `CapsuleError.permissionRequired(kind:.administrator, ...)`.

### 2.3 `CLICommandTests` — argv assertions

Pure synchronous `XCTAssertEqual(CLICommand.<builder>(...), [String literal])`. Example to mirror:
```swift
XCTAssertEqual(CLICommand.listVolumes(), ["volume", "list", "--format", "json"])
```

### 2.4 `RunConfigurationTests` — `.arguments` assertions

`XCTAssertEqual(config.arguments, [...])`. For M8 create new `VolumeConfigurationTests` / `NetworkConfigurationTests` / `DNSConfigurationTests` files in `Tests/CapsuleUnitTests` following this exact form (ordering, optional omission, size suffix, repeated `--opt`/`--label`/`--option`).

### 2.5 `MockBackend` — `Sources/CapsuleBackend/MockBackend.swift`

`public final class MockBackend: ContainerBackend, @unchecked Sendable` guarded by an `NSLock` + `private func withState<T>(_ body:) throws -> T` (throws injected `failure` first). Init (current):
```swift
public init(
    containers: [ContainerSummary] = MockBackend.sampleContainers,
    images: [ImageSummary] = MockBackend.sampleImages,
    volumes: [VolumeSummary] = [],
    networks: [NetworkSummary] = MockBackend.sampleNetworks,
    registries: [RegistrySummary] = [],
    machines: [MachineSummary] = [],
    version: BackendVersion = BackendVersion(client: "1.0.0", server: "1.0.0"),
    builder: BuilderStatus = BuilderStatus(isRunning: false),
    logLines: [OutputLine] = MockBackend.sampleLogLines,
    systemRunState: SystemRunState = .running,
    sampleStats: [ContainerStatsSample] = MockBackend.sampleStatsDefault)
```
Failure injection: `public var failure: BackendError?` (thrown by every `throws` command via `withState`); also `startFailure`, `stopDelay`, `neverEndingLogStream`. Recorded-call props are `public private(set)` and named `last*` / counters: `lastStopOptions, lastKillSignal, lastExportURL, lastTag, lastSavedURL, lastLoadedURL, prunedAll, lastLogin, lastTest, lastLogout, statsCallCount, logStreamTerminations, lastRunConfig, lastBuildConfig, lastCopy, lastListedDirectory`. Unseeded lists return `[]` (e.g. `listVolumes` returns seeded `volumes`, default empty). Sample data is in an `extension MockBackend` (e.g. `sampleNetworks` = one `default` network).

### 2.6 `Fixture` + Package resources

`Tests/CapsuleUnitTests/Fixtures.swift`:
```swift
enum Fixture {
    static func data(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> Data
        // Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
    static func text(_ name: String) -> String   // String(decoding: data(name), as: UTF8.self)
}
```
Fixture files live in **`Tests/CapsuleUnitTests/Fixtures/`** as `<name>.json`. Existing: `builder-status, containers-ls, containers-ls-empty, image-inspect, images-ls, machine-ls, network-ls, registry-ls, system-version, volume-ls-empty` (+ `README.md`). **Package.swift bundles them** via the test target's `resources: [.copy("Fixtures")]` (only on `CapsuleUnitTests`). New M8 fixtures (`volume-ls`, `volume-inspect`, `network-inspect`, `dns-ls`) are auto-bundled by the same `.copy("Fixtures")` — no Package.swift change needed; just drop `.json` files in the folder and document provenance in `Fixtures/README.md`.

---

## 3. License header for NEW files (copy verbatim)

Every new `.swift` file MUST begin with this block (replace only `<FileName>.swift`; keep `Capsule`, the year `2026`, and owner exactly). It is followed by a blank line, optional file-purpose comment lines (`//  …`), then imports.

```swift
//
//  <FileName>.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
```

Domain files that must not import UI/Process additionally carry the convention comment (copy when applicable):
```swift
//
//  NOTE: This module must remain free of UI and of `Foundation.Process`.
```

Run `make format` before committing (pre-commit hooks run swift-format + the license-header check).

---

## 4. NEW M8 types & signatures — CANONICAL (use these names verbatim)

### 4.1 `ContainerBackend` additions (`Sources/CapsuleBackend/ContainerBackend.swift`)

```swift
// Volumes
func inspectVolume(names: [String]) async throws -> Parsed<[VolumeSummary]>
func createVolume(_ config: VolumeConfiguration) async throws
func deleteVolumes(names: [String]) async throws
func pruneVolumes() async throws -> PruneResult

// Networks
func inspectNetwork(names: [String]) async throws -> Parsed<[NetworkSummary]>
func createNetwork(_ config: NetworkConfiguration) async throws
func deleteNetworks(names: [String]) async throws
func pruneNetworks() async throws -> PruneResult

// DNS (LIST ONLY — create/delete are privileged, via the sudo Terminal handoff §4.6/§7)
func listDNSDomains() async throws -> [DNSDomainSummary]
```

> **CONTRACT DECISION (prune return type):** Spec §4.1 wrote `pruneVolumes()/pruneNetworks()` as bare `async throws`, but §5.3 requires the model's `prune()` to surface "the CLI reclaimed message or 'Cleanup complete.'". To satisfy §5.3 and stay consistent with the existing `pruneContainers()`/`pruneImages(all:)` (both `-> PruneResult`), **the backend methods return `PruneResult`.** Implement them exactly like `pruneContainers()` (use `runner.run`, treat only a non-zero exit as failure, then `OutputParser.parsePruneResult(stdout:stderr:)`). The model maps `PruneResult` → `PruneSummary(message: result.reclaimedDescription ?? "Cleanup complete.")`.

> **CONTRACT DECISION (attachment data on `ContainerSummary`):** §5.5 needs `configuration.mounts[].source` and `configuration.networks[].network` from `container list -a`. Extend `ContainerSummary` (backend) with two **defaulted** fields so existing call sites/tests keep compiling:
> ```swift
> public var volumeMounts: [String]   // default []  (configuration.mounts[].source, non-nil)
> public var networkNames: [String]   // default []  (configuration.networks[].network)
> // init gains:  volumeMounts: [String] = [], networkNames: [String] = []  (appended LAST)
> ```
> Mirror them onto the domain `Container` (see §5.x). These are populated by `parseContainers`; everywhere else they default empty.

### 4.2 Configurations (`Sources/CapsuleBackend/`, beside RunConfiguration)

```swift
public struct VolumeConfiguration: Sendable, Equatable {
    public var name: String
    public var size: String?            // rendered as -s <value>; pre-validated K/M/G/T/P suffix
    public var options: [String]        // "k=v" tokens -> --opt
    public var labels: [String]         // "k=v" tokens -> --label
    public init(name: String, size: String? = nil, options: [String] = [], labels: [String] = [])
    public var arguments: [String] {
        var argv = ["volume", "create"]
        for label in labels { argv += ["--label", label] }
        for opt in options { argv += ["--opt", opt] }
        if let size { argv += ["-s", size] }
        argv.append(name)
        return argv
    }
}

public struct NetworkConfiguration: Sendable, Equatable {
    public var name: String
    public var subnet: String?
    public var subnetV6: String?
    public var `internal`: Bool
    public var options: [String]        // "k=v" -> --option
    public var labels: [String]         // "k=v" -> --label
    public var plugin: String?
    public init(name: String, subnet: String? = nil, subnetV6: String? = nil,
                internal: Bool = false, options: [String] = [], labels: [String] = [],
                plugin: String? = nil)
    public var arguments: [String] {
        var argv = ["network", "create"]
        if `internal` { argv.append("--internal") }
        for label in labels { argv += ["--label", label] }
        for opt in options { argv += ["--option", opt] }
        if let plugin { argv += ["--plugin", plugin] }
        if let subnet { argv += ["--subnet", subnet] }
        if let subnetV6 { argv += ["--subnet-v6", subnetV6] }
        argv.append(name)
        return argv
    }
}

public struct DNSConfiguration: Sendable, Equatable {
    public var domain: String
    public var localhostIP: String?
    public init(domain: String, localhostIP: String? = nil)
    /// Privileged create argv — consumed by DNSModel + the sudo Terminal handoff; NEVER runChecked.
    public var arguments: [String] {
        var argv = ["system", "dns", "create"]
        if let localhostIP { argv += ["--localhost", localhostIP] }
        argv.append(domain)
        return argv
    }
    /// Privileged delete argv companion.
    public var deleteArguments: [String] { ["system", "dns", "delete", domain] }
}
```

### 4.3 Value-type changes (`Sources/CapsuleBackend/BackendResourceTypes.swift`)

```swift
public struct VolumeSummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String { name }
    public var name: String
    public var source: String?
    public var sizeBytes: Int64?
    public var options: [String: String]   // default [:]
    public var labels: [String: String]    // default [:]
    public var createdAt: String?           // raw ISO-8601, domain parses to Date
    public init(name: String, source: String? = nil, sizeBytes: Int64? = nil,
                options: [String: String] = [:], labels: [String: String] = [:],
                createdAt: String? = nil)
}

public struct NetworkSummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var name: String
    public var mode: String?
    public var gateway: String?
    public var subnet: String?
    public var plugin: String?
    public var ipv6Subnet: String?
    public var labels: [String: String]     // default [:]
    public var createdAt: String?
    public var isBuiltin: Bool               // default false
    public init(id: String, name: String, mode: String? = nil, gateway: String? = nil,
                subnet: String? = nil, plugin: String? = nil, ipv6Subnet: String? = nil,
                labels: [String: String] = [:], createdAt: String? = nil, isBuiltin: Bool = false)
}

public struct DNSDomainSummary: Sendable, Equatable, Identifiable, Codable {
    public var id: String { domain }
    public var domain: String
    public var localhostIP: String?
    public init(domain: String, localhostIP: String? = nil)
}
```
> **`MockBackend.sampleNetworks` and any existing `NetworkSummary(...)` call sites keep compiling** because all new fields are defaulted. Add the `init` params in the order shown.

### 4.4 Wire-model changes (`Sources/CapsuleCLIBackend/WireModels.swift`)

```swift
struct CLINetworkRecord: Decodable {
    let id: String
    let configuration: Configuration
    let status: Status?
    struct Configuration: Decodable {
        let name: String
        let mode: String?
        let plugin: String?
        let labels: [String: String]?
        let options: [String: String]?
        let creationDate: String?
    }
    struct Status: Decodable {
        let ipv4Gateway: String?
        let ipv4Subnet: String?
        let ipv6Subnet: String?
    }
    var isBuiltin: Bool {                 // derivation lives on the wire record
        configuration.labels?["com.apple.container.resource.role"] == "builtin"
    }
}

struct CLIVolumeRecord: Decodable {       // lenient; exact keys pinned by Phase-1 volume-ls fixture
    let name: String?
    let source: String?
    let format: String?                   // driver
    let options: [String: String]?
    let labels: [String: String]?
    let size: Int64?
    let createdAt: String?
}

struct CLIDNSRecord: Decodable {          // lenient; pinned by Phase-1 dns-ls fixture
    let domain: String?
    let name: String?                     // accept either key
    let localhost: String?
}

// CLIContainerRecord.Configuration GAINS (for the attachment cross-reference, §5.5):
struct ConfiguredMount: Decodable { let source: String? }
let mounts: [ConfiguredMount]?
struct ConfiguredNetwork: Decodable { let network: String? }   // distinct from Status.Attachment
let networks: [ConfiguredNetwork]?
```

### 4.5 New `CLICommand` builders (`Sources/CapsuleCLIBackend/CLICommand.swift`)

```swift
public static func inspectVolume(names: [String]) -> [String] {
    ArgumentBuilder("volume", "inspect").adding(contentsOf: names).arguments
}                                            // ["volume","inspect"] + names  (NO --format)
public static func createVolume(_ config: VolumeConfiguration) -> [String] { config.arguments }
public static func deleteVolumes(names: [String]) -> [String] {
    ArgumentBuilder("volume", "delete").adding(contentsOf: names).arguments
}
public static func pruneVolumes() -> [String] { ArgumentBuilder("volume", "prune").arguments }

public static func inspectNetwork(names: [String]) -> [String] {
    ArgumentBuilder("network", "inspect").adding(contentsOf: names).arguments
}
public static func createNetwork(_ config: NetworkConfiguration) -> [String] { config.arguments }
public static func deleteNetworks(names: [String]) -> [String] {
    ArgumentBuilder("network", "delete").adding(contentsOf: names).arguments
}
public static func pruneNetworks() -> [String] { ArgumentBuilder("network", "prune").arguments }

public static func listDNSDomains() -> [String] {
    ArgumentBuilder("system", "dns", "list").flag("--format", "json").arguments
}                                            // ["system","dns","list","--format","json"]
```
> DNS **create/delete are NOT `CLICommand` builders** (Domain can't import `CapsuleCLIBackend`). They come from `DNSConfiguration.arguments` / `.deleteArguments` and are executed via the sudo Terminal handoff (§4.6/§7), never `runChecked`.

### 4.6 `OutputParser` additions (`Sources/CapsuleCLIBackend/OutputParser.swift`)

```swift
public static func parseVolumes(_ data: Data) throws -> [VolumeSummary]      // EXTEND existing
public static func parseNetworks(_ data: Data) throws -> [NetworkSummary]    // EXTEND existing (plugin/ipv6/labels/isBuiltin)
public static func parseDNS(_ data: Data) throws -> [DNSDomainSummary]       // NEW
```
All use the existing `lossyList(_:decode:)` (skip malformed rows). `inspectVolume`/`inspectNetwork` in the adapter pair `(try? OutputParser.parseVolumes/Networks(...))` with the raw stdout into `Parsed<[...]>` (mirror `inspectContainer`/`inspectImage`).

### 4.7 Domain models (`Sources/CapsuleDomain/`)

```swift
public struct Volume: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var source: String?
    public var sizeBytes: Int64?
    public var options: [String: String]
    public var labels: [String: String]
    public var createdAt: Date?
    public var attachedContainers: [String]    // derived (default [])
    public init(name:source:sizeBytes:options:labels:createdAt:attachedContainers:)
    public init(summary: VolumeSummary, attachedContainers: [String] = [])
}

public struct Network: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var mode: String?
    public var plugin: String?
    public var ipv4Subnet: String?
    public var ipv4Gateway: String?
    public var ipv6Subnet: String?
    public var `internal`: Bool
    public var labels: [String: String]
    public var createdAt: Date?
    public var connectedContainers: [String]   // derived (default [])
    public var isBuiltin: Bool
    public init(...)
    public init(summary: NetworkSummary, connectedContainers: [String] = [])
}

public struct DNSDomain: Sendable, Equatable, Identifiable {
    public var id: String { domain }
    public var domain: String
    public var localhostIP: String?
    public init(domain: String, localhostIP: String? = nil)
    public init(summary: DNSDomainSummary)
}

// Container (domain) GAINS, mirroring the backend extension:
public var volumeMounts: [String]   // default []
public var networkNames: [String]   // default []
```
Date parsing: reuse `Container.parseDate(_:)` (already `static` on `Container`, tolerant of fractional seconds).

### 4.8 Inspection wrappers + browser models

```swift
public struct VolumeInspection: Sendable, Equatable { public var value: Volume?;   public var rawJSON: String;  public init(value:rawJSON:) }
public struct NetworkInspection: Sendable, Equatable { public var value: Network?; public var rawJSON: String; public init(value:rawJSON:) }

public enum VolumeLoadState: Sendable, Equatable { case idle, loading, loaded; case unavailable(ErrorDetail) }
public enum NetworkLoadState: Sendable, Equatable { case idle, loading, loaded; case unavailable(ErrorDetail) }

@MainActor @Observable
public final class VolumeBrowserModel {
    public private(set) var allVolumes: [Volume]
    public private(set) var loadState: VolumeLoadState
    public var searchText: String
    public var selection: Set<Volume.ID>
    public var rows: [Volume] { /* search + sort */ }
    public init(backend: any ContainerBackend,
                normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel.defaultNormalize,
                onActivity: @escaping @MainActor (String) -> Void = { _ in })
    public func refresh() async                         // also builds AttachmentIndex, stamps attachedContainers
    public func inspect(name: String) async -> VolumeInspection
}

@MainActor @Observable
public final class NetworkBrowserModel {
    public private(set) var allNetworks: [Network]
    public private(set) var loadState: NetworkLoadState
    public var searchText: String
    public var selection: Set<Network.ID>
    public var rows: [Network] { ... }
    public init(backend:normalize:onActivity:)          // same shape as VolumeBrowserModel
    public func refresh() async                         // stamps connectedContainers
    public func inspect(name: String) async -> NetworkInspection
}
```
Mirror `ContainerBrowserModel` exactly (`@MainActor @Observable`, `private(set)` list + loadState, `defaultNormalize`, `onActivity` default). `refresh()` additionally calls `backend.listContainers(all: true)`, builds an `AttachmentIndex`, and stamps `attachedContainers`/`connectedContainers`.

### 4.9 Actions models

```swift
@MainActor @Observable
public final class VolumeActionsModel {
    public private(set) var busy: Set<String>
    public var notice: LifecycleNotice?
    public var confirmation: ConfirmationRequest?
    public init(backend: any ContainerBackend,
                normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel.defaultNormalize,
                onActivity: @escaping @MainActor (String) -> Void = { _ in },
                reloadList: @escaping @MainActor () async -> Void = {})
    @discardableResult public func create(_ config: VolumeConfiguration) async -> Bool
    public func delete(name: String) async
    public func deleteAll(names: [String]) async
    @discardableResult public func prune() async -> PruneSummary
    public func computePruneTargets() async -> [Volume]       // zero-attachment, best-effort (§9.4)
    // Draft validation (§5.4):
    public func validatedConfiguration(_ draft: VolumeDraft) -> Result<VolumeConfiguration, CapsuleError>
}

@MainActor @Observable
public final class NetworkActionsModel {
    public private(set) var busy: Set<String>
    public var notice: LifecycleNotice?
    public var confirmation: ConfirmationRequest?
    public init(backend:normalize:onActivity:reloadList:)     // same shape as VolumeActionsModel
    @discardableResult public func create(_ config: NetworkConfiguration) async -> Bool
    public func delete(name: String) async                    // refuses builtin (no-op + notice or guarded in UI)
    public func deleteAll(names: [String]) async              // excludes builtins
    @discardableResult public func prune() async -> PruneSummary
    public func computePruneTargets() async -> [Network]      // zero-connection, builtins excluded
    public func validatedConfiguration(_ draft: NetworkDraft,
                                       against existingNetworks: [Network]) -> Result<NetworkConfiguration, CapsuleError>
}
```
Follow `ImageActionsModel`: `busy` set during in-flight ops, failures surfaced via `notice = LifecycleNotice(detail: normalize(error).detail)`, each successful mutation calls `reloadList()`, **no new `OperationKind`/Activity tasks** (§9.1). `prune()` returns `PruneSummary(message: result.reclaimedDescription ?? "Cleanup complete.")`.

### 4.10 Drafts (`Sources/CapsuleDomain/`)

```swift
public struct VolumeDraft: Sendable, Equatable {
    public var name: String
    public var size: String           // raw, e.g. "10G"
    public var options: [KeyValueRow] // UI rows -> "k=v"
    public var labels: [KeyValueRow]
    public init(...)
}
public struct NetworkDraft: Sendable, Equatable {
    public var name: String
    public var subnet: String
    public var subnetV6: String
    public var isInternal: Bool
    public var options: [KeyValueRow]
    public var labels: [KeyValueRow]
    public var plugin: String
    public init(...)
}
public struct DNSDraft: Sendable, Equatable {
    public var domain: String
    public var localhostIP: String
    public init(domain: String = "", localhostIP: String = "")
}
public struct KeyValueRow: Sendable, Equatable, Identifiable {   // reusable advanced-options row
    public var id: UUID
    public var key: String
    public var value: String
    public init(id: UUID = UUID(), key: String = "", value: String = "")
    public var token: String? { key.isEmpty ? nil : "\(key)=\(value)" }
}
```
`validatedConfiguration` returns `.failure(.invalidInput(field:message:))` on empty/invalid required fields; for networks it also runs the subnet-conflict check (§4.13) and fails with `.invalidInput(field: "subnet", message:)`.

### 4.11 `AttachmentIndex` + input type (`Sources/CapsuleDomain/`)

```swift
public struct ContainerAttachmentInfo: Sendable, Equatable {
    public var containerName: String
    public var volumeSources: [String]   // configuration.mounts[].source
    public var networkNames: [String]    // configuration.networks[].network
    public init(containerName: String, volumeSources: [String], networkNames: [String])
    public init(container: Container)     // maps from the domain Container (name, volumeMounts, networkNames)
}

public struct AttachmentIndex: Sendable, Equatable {
    public let volumes: [String: [String]]    // volumeName -> [containerName]
    public let networks: [String: [String]]   // networkName -> [containerName]
    public init(volumes: [String: [String]], networks: [String: [String]])
    public func containers(forVolume name: String) -> [String]    // [] when none
    public func containers(forNetwork name: String) -> [String]
    public static func build(from containers: [ContainerAttachmentInfo]) -> AttachmentIndex
}
```
Pure, fully unit-tested (`AttachmentIndexTests`). Browser models build `[ContainerAttachmentInfo]` from `backend.listContainers(all: true).map(Container.init(summary:)).map(ContainerAttachmentInfo.init(container:))`.

### 4.12 CIDR helper (`Sources/CapsuleDomain/CIDR.swift`)

```swift
public enum CIDR {
    public struct Parsed: Sendable, Equatable {
        public var bytes: [UInt8]      // 4 (IPv4) or 16 (IPv6) network-address bytes
        public var prefixLength: Int
        public var isIPv6: Bool
    }
    public static func parse(_ text: String) -> Parsed?            // nil on malformed
    public static func overlaps(_ lhs: String, _ rhs: String) -> Bool   // false if families differ or either malformed
}
```
Used by network draft validation (§4.13). Tested by `CIDRTests` (overlap/parse, IPv4 + IPv6, malformed).

### 4.13 Subnet-conflict validation (CANONICAL placement)

> **CONTRACT DECISION:** Spec §5.6 says `NetworkModel.validate(...)`, but the canonical models are `NetworkBrowserModel`/`NetworkActionsModel` (there is no `NetworkModel`). Lock the conflict check as a **pure static function in the Domain** (testable in isolation) plus the model method that calls it:

```swift
public enum NetworkValidation {
    /// nil = no conflict. Non-nil = inline message naming the conflicting network, e.g.
    /// "Subnet 10.0.0.0/24 overlaps with network 'default' (192.168.64.0/24)."
    /// Empty subnet -> nil (CLI auto-assigns). Malformed subnet -> a syntax message with an example.
    public static func subnetConflict(subnet: String,
                                      against existingNetworks: [Network]) -> String?
}
```
`NetworkActionsModel.validatedConfiguration(_:against:)` calls this; a non-nil result becomes `.invalidInput(field: "subnet", message:)` and disables Create in the UI.

### 4.14 `ConfirmationKind` additions (`Sources/CapsuleDomain/Confirmation.swift`)

```swift
public enum ConfirmationKind: Sendable, Equatable {
    case kill
    case delete(force: Bool)
    case exportNotStopped
    case deleteImage
    // M8 — NO force variants (no --force exists):
    case deleteVolume
    case deleteNetwork
    case pruneVolumes
    case pruneNetworks
}
```
Builders on `ConfirmationRequest` (return `nil` to mean "no confirmation needed / disallowed"):
```swift
public static func deleteVolume(names: [String], attachments: AttachmentIndex) -> ConfirmationRequest?
    // message: "Deleting <name> permanently destroys its data."
    //   + (if attached) " It is mounted by: <names>; delete will fail until they are removed."
public static func deleteNetwork(name: String, isBuiltin: Bool, attachments: AttachmentIndex) -> ConfirmationRequest?
    // returns nil when isBuiltin (UI disables Delete);
    // message: "Delete network <name>?" + (if connected) " Connected containers: <names>."
public static func pruneVolumes() -> ConfirmationRequest
public static func pruneNetworks() -> ConfirmationRequest
```

### 4.15 `DNSModel` + privileged handoff (`Sources/CapsuleDomain/DNSModel.swift`)

```swift
public enum DNSLoadState: Sendable, Equatable { case idle, loading, loaded; case unavailable(ErrorDetail) }

@MainActor @Observable
public final class DNSModel {
    public private(set) var domains: [DNSDomain]
    public private(set) var loadState: DNSLoadState
    public var notice: LifecycleNotice?

    public init(backend: any ContainerBackend,
                normalize: @escaping @Sendable (any Error) -> CapsuleError = SystemStatusModel.defaultNormalize,
                onActivity: @escaping @MainActor (String) -> Void = { _ in },
                runPrivilegedInTerminal: @escaping @MainActor ([String]) -> Void)

    public func refresh() async                                   // unprivileged list; [] => "No local DNS domains"
    @discardableResult
    public func addDomain(_ draft: DNSDraft) -> Result<Void, CapsuleError>  // validate -> hand off DNSConfiguration.arguments
    public func deleteDomain(_ domain: String)                    // hand off DNSConfiguration(domain:).deleteArguments
}
```
> **`runPrivilegedInTerminal` closure signature is canonical:** `@MainActor ([String]) -> Void`. `addDomain`/`deleteDomain` build the argv from `DNSConfiguration` and pass it to this closure (the App layer prefixes `sudo` + opens Terminal). `refresh()` distinguishes empty `[]` ("No local DNS domains") from `.unavailable(ErrorDetail)`. The closure is never `runChecked`; the in-process safety net is `permissionRequired(.administrator)` via `ErrorNormalizer` (§1.7).

### 4.16 App-layer wiring (`Sources/CapsuleApp/AppEnvironment.swift`)

The privileged handoff extends the existing `openCommandInTerminalApp(_:executablePath:)` with a `sudo` prefix. Canonical App-layer closure to inject into `DNSModel`:
```swift
let runPrivilegedInTerminal: @MainActor ([String]) -> Void = { argv in
    openPrivilegedCommandInTerminalApp(argv, executablePath: cliBackend.executableURL.path)
    shell.appendActivity("Opened in Terminal (sudo): \(argv.joined(separator: " "))")
}
```
Implement `openPrivilegedCommandInTerminalApp` beside `openCommandInTerminalApp`, reusing the existing private `shellQuote`, writing a `.command` script whose body is `exec sudo <resolved-container-path> <quoted args…>`, then `NSWorkspace.shared.open(url)` (same temp-file sweep). Also **implement the previously-stubbed `.grantPermission` case** in `AppEnvironment.makeActions(...)` to perform the same sudo handoff for the pending command (today it falls into the `editConfiguration, grantPermission` no-op branch — split `grantPermission(.administrator)` out and route it). New models (`VolumeBrowserModel`, `VolumeActionsModel`, `NetworkBrowserModel`, `NetworkActionsModel`, `DNSModel`) are added to the `AppEnvironment` struct + `init` + `live()` and threaded `backend` / `{ ErrorNormalizer.normalize($0) }` / `onActivity` / `reloadList`.

---

## 5. Build / test / check commands

- **Build:** `make build` (runs `swift build`).
- **Full tests:** `make test` (runs `swift test` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` exported — REQUIRED; XCTest needs full Xcode).
- **Focused test (class):**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter <TestCaseClass>`
- **Focused test (single method):**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter <TestCaseClass>/<testMethod>`
  e.g. `--filter CLICommandTests/testVolumeCommands`
- **Static checks:** `make check` (lint + arch guard + license headers).
- **Everything:** `make ci` = build + lint + arch + headers + test.
- **Formatting before commit:** `make format` (swift-format; pre-commit hooks also run the license-header check).

Arch guard (`Scripts/check-architecture.sh` + `ArchitectureGuardTests`): `CapsuleUI` imports NO Backend module; `CapsuleDomain` imports NO `CapsuleUI` and NO `Foundation.Process` (it MAY import `CapsuleBackend` — protocol + value types + `*Configuration`). `CapsuleApp` is the only composition root. New Domain files (`Volume`, `Network`, `DNSDomain`, browser/actions/DNS models, `AttachmentIndex`, `CIDR`, drafts, validation, confirmation builders) live in `CapsuleDomain` and may `import CapsuleBackend` + `Observation` + `Foundation` only.

Commit-message trailers (exactly, on the final two lines):
```
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QRY8sjZCmM87FEsjo8A4he
```
