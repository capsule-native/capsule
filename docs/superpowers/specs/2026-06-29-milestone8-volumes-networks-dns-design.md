# Milestone 8 · Volumes, Networks & DNS — Design

Status: approved-to-build (`/goal` directive; design forks confirmed with the user). Date: 2026-06-29.
Branch: `milestone-8-volumes-networks-dns` (cut from `main` after M7 merges; if M7 is still
unmerged, branch from `milestone-7-run-build-exec-logs-copy`).

## 1. Goal & scope

Phase 3 ("Systems surface") begins. Make Capsule a credible full wrapper by adding the
storage and networking surfaces, plus local DNS:

- **Volumes browser** from `volume list`: distinguish attached vs reclaimable volumes; an
  inspector with mount references where available; a **Create Volume** sheet with an
  **advanced disclosure** for lower-frequency options (size, driver options such as
  journaling, labels); **delete** (warn about attached containers and data loss); and
  **prune** with a candidate preview.
- **Networks browser** from `network list`: an inspector showing subnet/IPAM detail; a
  **Create Network** sheet that **validates subnet conflicts before launch** where possible;
  **delete** (warn when containers are attached); and **prune** with a candidate preview.
  Builtin networks (e.g. `default`) are protected from deletion.
- **Local DNS** under **Settings › Networking** backed by `system dns create/delete/list`.
  `create`/`delete` **require administrator privileges**: route them through a clean
  **direct Terminal handoff** with `sudo`. Listing needs no privilege; the UI differentiates
  "none configured" from "insufficient privilege for mutation," and **never fails silently** —
  it surfaces `permissionRequired(.administrator)` with a clear recovery path.
- Consistent destructive-action patterns throughout: single-item delete in **context menus**,
  bulk actions in the **toolbar**, **confirmation sheets** for many-item or data-destroying
  operations, and **previews** before any prune/delete.

**Out of scope (YAGNI):** a privileged launchd/`SMAppService` helper (the Terminal handoff is
the sanctioned path); "suggest next free subnet" auto-fill (we detect+report conflicts, no
auto-pick); saved scopes for volumes/networks (the container/image scope machinery is not
needed at this volume of rows); live volume-usage metrics over time; an in-app password
prompt for `sudo` (Terminal owns the credential prompt).

## 2. CLI facts (verified against `container` v1.0.0 `--help`, services running, on this machine)

```
volume create  [--label <k=v> ...] [--opt <k=v> ...] [-s <size>] <name>
                 (-s size accepts K/M/G/T/P suffix; NO --driver / --source / --name flags)
volume delete  [-a/--all] [<names> ...]                 (NO --force)
volume list    [--format json|table|yaml|toml] [-q/--quiet]
volume inspect <names> ...                              (JSON by default; NO --format flag)
volume prune                                            (removes volumes with no container refs; no args)

network create [--internal] [--label <k=v> ...] [--option <k=v> ...] [--plugin <p>]
                 [--subnet <cidr>] [--subnet-v6 <cidr>] <name>
                 (gateway is derived from subnet, not set directly; default plugin
                  container-network-vmnet)
network delete [-a/--all] [<network-names> ...]         (NO --force)
network list   [--format json|...] [-q/--quiet]
network inspect <networks> ...                          (JSON by default; NO --format flag)
network prune                                           (removes networks with no connections; no args)

system dns list   [--format json|table|yaml|toml] [-q/--quiet]   (NO privilege required)
system dns create [--localhost <ip>] <domain-name>      (MUST run as administrator)
system dns delete <domain-name>                         (MUST run as administrator)
```

Observed error/JSON shapes (real captures):

- `system dns create capsule.test` **without** sudo → exit **1**, stderr
  `Error: cannot create domain (try sudo?)`. `delete` → `Error: cannot delete domain (try sudo?)`.
  The `(try sudo?)` substring (and the help string "must run as an administrator") is the
  **normalization signal** for `permissionRequired(.administrator)`.
- `system dns list --format json` with none configured → `[]` (exit 0). This is how the UI
  tells "none configured" apart from a privilege failure.
- `network list --format json` →
  `[{"configuration":{"creationDate":"…","labels":{"com.apple.container.resource.role":"builtin"},
  "mode":"nat","name":"default","options":{},"plugin":"container-network-vmnet"},"id":"default",
  "status":{"ipv4Gateway":"192.168.64.1","ipv4Subnet":"192.168.64.0/24","ipv6Subnet":"fdb6:…/64"}}]`.
  The `com.apple.container.resource.role: builtin` label marks **protected** networks.
- `volume delete <missing>` → exit **1**, `Error: failed to delete one or more volumes: ["…"]`.
- `container list -a --format json` exposes `configuration.networks` (e.g.
  `[{"network":"default","options":{…}}]`) and `configuration.mounts` — the data behind the
  **attachment cross-reference**. (`mounts` is empty for an unmounted container; the exact
  volume-mount shape is pinned with a real fixture in Phase 1.)
- `volume list` and `dns list` are **empty** on this machine, so their decode fixtures are
  captured in Phase 1 by creating throwaway resources; the sudo-gated DNS fixture is
  hand-built schema-faithfully with documented provenance.

`volume inspect` / `network inspect` have **no `--format` flag** — they emit pretty JSON
arrays by default, parsed with the same lenient decode + `Parsed<T>` raw-fallback used
elsewhere.

## 3. Architecture & layering

Obeys the arch-guard rules (UI imports no `CapsuleBackend`; Domain imports no UI and no
`Process`). Reuses every M5–M7 seam: the resource **browser/inspector** stack
(`*BrowserModel` + `*ListView` + `*InspectorView`), the **draft-model + `validatedConfiguration()`
+ command-preview** sheet stack, the pure **`ConfirmationRequest`/`ConfirmationKind`** +
generic `ConfirmationSheet`, the **prune-preview** sheet (precompute → list → honest
post-result), the **`LifecycleNotice` → `ErrorDetail` → `RecoveryActionButtons`** error path,
the **capability flags** (`BackendFeature`/`SystemFeature`), and the M7 **`openCommandInTerminalApp`**
handoff.

No new architectural concepts are introduced. The deliberate divergences from the
exploration's first guesses are documented in §9 (Decisions).

## 4. Backend layer (`CapsuleBackend` + `CapsuleCLIBackend`)

### 4.1 Protocol (`ContainerBackend`)
Add (all `async throws`; `list*` already exist):

```
func inspectVolume(names: [String]) async throws -> Parsed<[VolumeSummary]>
func createVolume(_ config: VolumeConfiguration) async throws
func deleteVolumes(names: [String]) async throws
func pruneVolumes() async throws

func inspectNetwork(names: [String]) async throws -> Parsed<[NetworkSummary]>
func createNetwork(_ config: NetworkConfiguration) async throws
func deleteNetworks(names: [String]) async throws
func pruneNetworks() async throws

func listDNSDomains() async throws -> [DNSDomainSummary]
// create/delete are NOT backend methods — they are privileged and run via the Terminal
// handoff (see §7). The backend only ever LISTS dns (unprivileged).
```

### 4.2 argv (single source of truth: `*Configuration.arguments` + `CLICommand`)
`CLICommand` static builders return `[String]`; mutating builders take the typed config:

| Builder | argv |
|---|---|
| `inspectVolume(names)` | `["volume","inspect"] + names` |
| `createVolume(config)` | `config.arguments` → `["volume","create"] + (--label …) + (--opt …) + (-s <size>) + [name]` |
| `deleteVolumes(names)` | `["volume","delete"] + names` |
| `pruneVolumes()` | `["volume","prune"]` |
| `inspectNetwork(names)` | `["network","inspect"] + names` |
| `createNetwork(config)` | `config.arguments` → `["network","create"] + (--internal) + (--label …) + (--option …) + (--plugin p) + (--subnet s) + (--subnet-v6 s6) + [name]` |
| `deleteNetworks(names)` | `["network","delete"] + names` |
| `pruneNetworks()` | `["network","prune"]` |
| `listDNSDomains()` | `["system","dns","list","--format","json"]` (only DNS verb the backend runs) |

DNS **create/delete** argv is **not** a `CLICommand` (Domain cannot import `CapsuleCLIBackend`).
It comes from `DNSConfiguration.arguments` (in `CapsuleBackend`, see §4.6) → e.g.
`["system","dns","create"] + (--localhost ip) + [domain]` and
`["system","dns","delete", domain]`. The Domain model builds it from `DNSConfiguration` and the
App layer executes it via the `sudo` Terminal handoff (§7) — never `runChecked`. This mirrors
M7, where `RunConfiguration.arguments` feeds both the CLI adapter and the Terminal handoff.

### 4.3 Wire models + parsers (`WireModels.swift`, `OutputParser.swift`)
- Extend `CLINetworkRecord` to capture `configuration.{plugin,labels,options,creationDate}`
  and `status.ipv6Subnet`. Add `isBuiltin` derivation from
  `labels["com.apple.container.resource.role"] == "builtin"`.
- Add `CLIVolumeRecord` (lenient: `name?`, `source?`, `format?`/driver, `options?`, `labels?`,
  `size?`, `createdAt?` — exact keys pinned by Phase-1 fixture).
- Add `CLIDNSRecord` (lenient: `domain`/`name`, `localhost?` — pinned by Phase-1 fixture; the
  `-q/--quiet` plain-line form is a documented fallback if JSON shape surprises us).
- `OutputParser.parseVolumes/parseNetworks/parseDNS` use the existing `lossyList` (skip
  malformed rows) and pair with raw payload for inspect.

### 4.4 Value types (`BackendResourceTypes.swift`)
Extend `VolumeSummary` (add `sizeBytes?`, `options`, `labels`, `createdAt?`) and
`NetworkSummary` (add `plugin?`, `ipv6Subnet?`, `labels`, `createdAt?`, `isBuiltin`). Add
`DNSDomainSummary` (`domain`, `localhostIP?`). All `Sendable`/`Equatable`/`Identifiable`/`Codable`.

### 4.5 `MockBackend`
Seedable `volumes`/`networks`/`dnsDomains`; failure injection; records last create/delete/prune
argv for assertions. Returns `[]` for unseeded lists.

### 4.6 Configurations (argv single-source-of-truth; in `CapsuleBackend`)
Placed beside `RunConfiguration`/`BuildConfiguration`. Each is `Sendable`/`Equatable` with a
computed `arguments: [String]`:
- `VolumeConfiguration`: `name`, `size?` (rendered as `-s <value>`), `options: [String]` (`--opt k=v`),
  `labels: [String]` (`--label k=v`). Order: `["volume","create"]` + labels + opts + size + `[name]`.
- `NetworkConfiguration`: `name`, `subnet?`, `subnetV6?`, `internal: Bool`, `options: [String]`,
  `labels: [String]`, `plugin?`. Order: `["network","create"]` + `(--internal)` + labels +
  options + `(--plugin)` + `(--subnet)` + `(--subnet-v6)` + `[name]`.
- `DNSConfiguration`: `domain`, `localhostIP?`. `arguments` → `["system","dns","create"] +
  (--localhost ip) + [domain]`; a companion `deleteArguments` → `["system","dns","delete", domain]`.
  Consumed by the Domain `DNSModel` and the App-layer sudo handoff (§7); never `runChecked`.

## 5. Domain layer (`CapsuleDomain`)

### 5.1 Domain models (`Resource.swift` / new files)
- `Volume`: `id` (= name), `name`, `source?`, `sizeBytes?`, `options: [String:String]`,
  `labels: [String:String]`, `createdAt?`, `attachedContainers: [String]` (derived).
- `Network`: `id`, `name`, `mode?`, `plugin?`, `ipv4Subnet?`, `ipv4Gateway?`, `ipv6Subnet?`,
  `internal: Bool`, `labels`, `createdAt?`, `connectedContainers: [String]` (derived),
  `isBuiltin: Bool`.
- `DNSDomain`: `id` (= domain), `domain`, `localhostIP?`.

### 5.2 Browser models
`VolumeBrowserModel`, `NetworkBrowserModel` — `@Observable @MainActor`, mirror
`ContainerBrowserModel`: `allVolumes/allNetworks`, `loadState` (idle/loading/loaded/unavailable),
`searchText`, `selection: Set<ID>`, computed `rows`, `refresh()`, `inspect(name:)` →
`VolumeInspection`/`NetworkInspection` (`value` + `rawJSON`). On `refresh()`, also fetch the
attachment index (see §5.5) and stamp `attachedContainers`/`connectedContainers`.

### 5.3 Actions models
`VolumeActionsModel`, `NetworkActionsModel` — create/delete/prune as **synchronous** ops
(non-streaming, near-instant) using a `busy: Set<String>` for in-flight rows and a
`notice: LifecycleNotice?` on failure, exactly like `ImageActionsModel.tag/delete/prune`.
Each method calls `reloadList()` on success. **No new `OperationKind`/Activity tasks**
(decision §9.1). `prune()` returns a `PruneSummary` (CLI reclaimed message or "Cleanup complete.").

### 5.4 Drafts + validation
Configurations themselves live in `CapsuleBackend` (§4.6), alongside `RunConfiguration`/
`BuildConfiguration` — they are the argv single-source-of-truth shared by the CLI adapter and
(for DNS) the Terminal handoff. The Domain layer owns the **drafts** and the validation:

`VolumeDraft`/`NetworkDraft`/`DNSDraft` hold UI-friendly raw strings/rows. The model's
`validatedConfiguration() -> Result<Config, CapsuleError>` enforces required fields (and, for
networks, runs the subnet-conflict check of §5.6) and returns `.invalidInput(field:message:)`
on failure. Domain may build a `*Configuration` (a `CapsuleBackend` value type) — the same way
`RunModel` builds `RunConfiguration` today — but never imports `CapsuleCLIBackend`.

### 5.5 `AttachmentIndex` (pure)
`AttachmentIndex.build(from containers: [ContainerAttachmentInfo])` → maps
`volumeName -> [containerName]` and `networkName -> [containerName]`. Source data is
`configuration.mounts[].source` (volume) and `configuration.networks[].network` (network),
surfaced from `container list -a --format json`. Best-effort and as fresh as the last list.
Pure and fully unit-tested.

### 5.6 Subnet conflict (pure)
`CIDR.overlaps(_:_:)` (IPv4 + IPv6) and `CIDR.parse`. `NetworkModel.validate(draft, against:
existingNetworks)` returns an inline message when `draft.subnet` overlaps an existing
`status.ipv4Subnet`/`ipv6Subnet`, naming the conflicting network — e.g.
`"Subnet 10.0.0.0/24 overlaps with network 'default' (192.168.64.0/24)."` — and disables Create.
Empty subnet is allowed (CLI auto-assigns). Malformed CIDR yields a syntax message with an example.

### 5.7 Confirmation kinds (`Confirmation.swift`)
Add `.deleteVolume`, `.deleteNetwork`, `.pruneVolumes`, `.pruneNetworks`. **No force variants**
(no `--force` exists). Single delete proceeds via a confirmation that embeds the warning; bulk
always confirms. Builders compose the message from the attachment index:
- Volume: `"Deleting <name> permanently destroys its data."` + (if attached)
  `" It is mounted by: <container names>; delete will fail until they are removed."`
- Network: `"Delete network <name>?"` + (if connected) `" Connected containers: <names>."`
  Builtin networks return **no** request and the action is disabled in the UI.

## 6. UI layer (`CapsuleUI`)

- `VolumeListView` / `NetworkListView`: `Table(rows, selection:)`, `.searchable`, **context
  menu** (Inspect, Delete… `role:.destructive`) for single/selected rows, **toolbar**
  (Create…, Clean Up = prune, Refresh). Columns: name, (size | subnet), attachment count,
  created. Builtin networks show a lock affordance and a disabled Delete.
- `VolumeInspectorView` / `NetworkInspectorView`: `TabView` Summary + Raw JSON (copyable
  monospaced). Summary lists attached/connected containers (with the count prominent);
  network Summary shows mode/plugin/subnet/gateway/ipv6 as copyable fields.
- **Create Volume sheet:** Name (required) → `DisclosureGroup("Advanced Options")` with Size,
  driver `--opt` rows (journaling lives here), label rows. Live command preview. No
  confirmation (low risk).
- **Create Network sheet:** Name (required) + Subnet (optional, with CIDR hint and live
  conflict validation) → `DisclosureGroup("Advanced Options")` with IPv6 subnet, Internal
  toggle, plugin, `--option` rows, label rows. Live command preview.
- **Prune sheets** (`VolumePruneSheet`/`NetworkPruneSheet`): follow `ImagePruneSheet` —
  precompute best-effort targets (zero-attachment resources via the index, builtin networks
  excluded), list them with attachment annotations, an honest "this preview is best-effort;
  the runtime decides the final set — actual result shown after," then run and show the result.
- Wiring: `ContentColumnView` routes `.volumes`/`.networks`; `AppShellView` inspector switch
  adds the two inspectors; `RootView`/`AppEnvironment` instantiate the new models and thread
  `backend`/`normalize`/`onActivity`/`reloadList`.

## 7. DNS / Settings — direct sudo handoff

- New **Networking** tab in `PreferencesView` (`Label("Networking", systemImage: "network")`)
  hosting `NetworkingView` bound to `DNSModel` (`@Observable @MainActor`, mirrors
  `RegistriesModel`): `domains`, `loadState`, `notice`, `refresh()` (unprivileged list).
- The pane shows the domain list (distinguishing **empty `[]` = "No local DNS domains"** from a
  **load failure**), an **Add Domain…** sheet (domain name + optional localhost IP, validated),
  and per-row **Delete**. Both Add and Delete state **"Requires administrator — opens Terminal"**
  and hand off **directly**: `runPrivilegedInTerminal(argv)` writes a `.command` script
  `exec sudo <container-path> system dns create <domain>` and `NSWorkspace.open`s it (extends
  M7's `openCommandInTerminalApp`, adding the `sudo` prefix and reusing `shellQuote`).
- After a handoff the pane shows "Complete the operation in Terminal, then Refresh," and a
  Refresh re-lists. We do **not** attempt-then-fail in-process (decision §9.2).
- **`permissionRequired(.administrator)` safety net:** `ErrorNormalizer` gains an
  administrator-signature check (`try sudo?`, `must run as an administrator`) mapping to
  `CapsuleError.permissionRequired(.administrator, message:)` →
  `ErrorDetail(title:"Administrator access required", …, recoveryActions:[.grantPermission(.administrator), .openLogs])`.
  The previously-stubbed `.grantPermission` handler in `AppEnvironment.makeActions` is
  implemented to perform the same sudo Terminal handoff for the pending command. Nothing fails
  silently.

## 8. Capability gating

Reuse the M2 flags. `SystemFeature.volumes`/`.networks` already gate the sidebar rows; the
Create/Delete/Clean-Up controls additionally `.disabled` when the relevant feature is absent
or the service is down (`SystemHealth`). The DNS pane gates its controls on service
availability. On this build all three are supported, so the visible behavior is the
service-down path — but routing it through the capability set means an OS/build that lacks a
family **hides or disables** that UI rather than erroring (acceptance requirement). If a
sub-feature ever needs finer gating, add a `BackendFeature` case; family-level gating suffices now.

## 9. Decisions (with rationale)

1. **Create/delete/prune are synchronous, not Activity tasks.** They are non-streaming and
   near-instant; M6 already models image delete/prune this way (busy set + `LifecycleNotice`).
   Adding `OperationKind` cases would be ceremony without payoff. *(User-confirmed.)*
2. **DNS uses a direct sudo Terminal handoff**, not attempt-then-recover. Admin is *always*
   required, so an in-process first attempt is guaranteed to fail — pure friction. The buttons
   declare the requirement and hand off straight to Terminal; `permissionRequired` remains the
   safety net for any in-process path. *(User-confirmed.)*
3. **Cross-reference containers for attachment.** `volume/network inspect` do not list
   attached containers and there is no `--force`, so proactive warnings and accurate-ish prune
   previews require reading `container list`. This is the "credible full wrapper" value.
   *(User-confirmed.)*
4. **Prune previews are explicitly best-effort.** The CLI owns the authoritative reference
   check; our preview is computed from the attachment index and labeled as best-effort, with
   the real reclaimed set shown after — mirrors M6's honest image-prune messaging. *(User-confirmed.)*
5. **No force-delete semantics.** The CLI has no `--force` for volume/network delete. Deleting
   an in-use resource simply errors; we warn beforehand and surface the CLI error with recovery
   afterward. Confirmation `kind`s carry no `force` flag.
6. **Builtin networks are protected.** Networks labeled `…resource.role: builtin` (e.g.
   `default`) cannot be deleted; the UI disables Delete and excludes them from prune/bulk.

## 10. Testing strategy (TDD; XCTest)

- **argv:** `CLICommandTests` for every new builder; `VolumeConfigurationTests` /
  `NetworkConfigurationTests` for `.arguments` (ordering, optional omission, size suffix,
  repeated `--opt`/`--label`/`--option`).
- **backend:** `CLIContainerBackendTests` via `StubProcessRunner` — argv (`lastCall`), real
  fixture decode, error mapping including `(try sudo?)` → `permissionRequired(.administrator)`.
- **parsers/wire:** decode tests against Phase-1 fixtures (`volume-ls`, `volume-inspect`,
  `network-ls`, `network-inspect`, `dns-ls`).
- **pure domain:** `AttachmentIndexTests` (containers → maps), `CIDRTests` (overlap/parse,
  IPv4+IPv6, malformed), confirmation-builder tests (`deleteVolume`/`deleteNetwork`/prune
  messages; builtin returns nil).
- **models:** `VolumeBrowserModelTests`/`NetworkBrowserModelTests` (refresh/inspect/search/
  selection/loadState), `VolumeActionsModelTests`/`NetworkActionsModelTests` (create/delete/
  prune success + failure-surfacing via `notice`), `DNSModelTests` (list, empty-vs-error,
  handoff closure invoked with the right argv, `permissionRequired` surfaced).
- **normalization:** `ErrorNormalizationTests` for the administrator signatures.
- **integration:** `CLIBackendIntegrationTests` additions guarded by `CAPSULE_INTEGRATION=1`
  (create/list/inspect/delete/prune a throwaway volume and network against the real CLI).
- **close-out:** live GUI smoke (create/inspect/delete/prune a volume and a network; DNS Add
  opens Terminal with the correct `sudo` command; list distinguishes empty vs failure) +
  adversarial review, per the M5.5/M6/M7 tradition.

## 11. Acceptance

Volumes and networks **list, inspect, create** (with conflict/advanced handling), **delete,
and prune** correctly; **DNS create/delete route through the privileged Terminal path** with
explicit admin prompts and **never fail silently**; unsupported-on-this-build families are
hidden/disabled rather than erroring; **all destructive actions confirm**, with previews before
any prune/delete and proactive attachment/data-loss warnings.
