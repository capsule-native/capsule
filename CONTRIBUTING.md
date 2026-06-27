# Contributing to Capsule

## Project layout

Capsule is a Swift Package of strictly-layered modules (`Sources/`) plus a thin Xcode app
target (`App/`). Read the architecture section of the [README](README.md) first.

## Adding a command without touching the UI

The architecture is designed so that a new container command is a *backend + domain*
change, never a *view* change. To add one — say, "pause a container":

1. **Domain** — add a case to `ResourceAction` in
   [`Sources/CapsuleDomain/Action.swift`](Sources/CapsuleDomain/Action.swift):

   ```swift
   case pause(containerID: String)
   ```

2. **Backend port** — declare the capability on `ContainerBackend` in
   [`Sources/CapsuleBackend/ContainerBackend.swift`](Sources/CapsuleBackend/ContainerBackend.swift):

   ```swift
   func pause(containerID: String) async throws
   ```

3. **Adapter** — implement it in
   [`Sources/CapsuleCLIBackend`](Sources/CapsuleCLIBackend) using `ArgumentBuilder`
   + `ProcessRunner` + `OutputParser`. Add a unit test for the argument building.

4. **Domain orchestration** — expose it from `WorkspaceModel` (or a sibling) so the UI
   can invoke it through the domain.

The views in `CapsuleUI` bind to the domain and render whatever it exposes — they neither
know nor care which backend ran the command. This is enforced: `CapsuleUI` may not import
any backend module.

## Before you push

```sh
make check   # lint + architecture boundaries + license headers
make test    # unit tests
```

Or run everything CI runs: `make ci`.

- **Formatting**: `make format` (uses [`swift format`](.swift-format)).
- **License headers**: every Swift file starts with the standard header. Run
  `Scripts/add-headers.sh` to add it to new files; `make headers` verifies.
- **Git hooks**: `make hooks` installs a pre-commit hook that runs the lint + header
  checks on staged files. Run it once after cloning (or `make bootstrap`).

## Adding a module

New modules are SwiftPM targets in [`Package.swift`](Package.swift). Respect the
dependency direction: UI depends only on Domain; Domain depends only on the Backend port;
adapters depend on the port; the app target is the only composition root. If you introduce
a new forbidden edge, add it to both
[`ArchitectureGuardTests`](Tests/CapsuleUnitTests/ArchitectureGuardTests.swift) and
[`Scripts/check-architecture.sh`](Scripts/check-architecture.sh).
