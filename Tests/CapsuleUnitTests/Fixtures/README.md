# Test fixtures

Real `container --format json` captures used to verify the `CapsuleCLIBackend`
decoders without ever spawning the CLI in unit tests.

| File | Provenance |
|------|------------|
| `images-ls.json` | **Real capture** — `container image ls --format json` (CLI v1.0.0) after pulling `docker.io/library/alpine:latest`. |
| `system-version.json` | **Real capture** — `container system version --format json` (CLI v1.0.0, system service running) — client + `container-apiserver` entries. |
| `containers-ls-empty.json` | **Real capture** — `container ls --all --format json` with no containers (`[]`). |
| `network-ls.json` | **Real capture** — `container network ls --format json` (the built-in `default` NAT network). |
| `volume-ls-empty.json` | **Real capture** — `container volume ls --format json` (`[]`). |
| `registry-ls.json` | **Real capture** — `container registry ls --format json` (`[]`). |
| `machine-ls.json` | **Real capture** — `container machine ls --format json` (`[]`). |
| `builder-status.json` | **Real capture** — `container builder status --format json` (no builder configured → `[]`). |
| `containers-ls.json` | **Schema-faithful, hand-built.** Populating a real container list requires booting a Linux VM kernel, which was intentionally not installed on the dev machine. Shaped exactly to the `ManagedContainer` → `{id, configuration, status{state, networks[Attachment]}}` encoding in apple/container **1.0.0** (`ContainerSnapshot.swift`, `ContainerStatus.swift`, `Attachment.swift`), reusing the real alpine image descriptor. |
| `volume-ls.json` | **Real capture** — `container volume list --format json` (CLI v1.0.0) after `container volume create --label role=scratch -s 512M capsule-m8-probe`. Nested `{configuration{…}, id}` shape; `sizeInBytes`, `driver`, `format`, `options`, `labels`, `creationDate`. Throwaway volume deleted afterward. |
| `volume-inspect.json` | **Real capture** — `container volume inspect capsule-m8-probe` (pretty JSON array; `volume inspect` has no `--format` flag). Same record as `volume-ls.json`. |
| `network-inspect.json` | **Real capture** — `container network inspect capsule-m8-net` for a **non-builtin** network created with `--label tier=test --subnet 10.88.0.0/24` (so `isBuiltin == false`). Carries `configuration.{plugin,labels,creationDate}` and `status.{ipv4Gateway,ipv4Subnet,ipv6Subnet}`. Throwaway network deleted afterward. |
| `dns-ls.json` | **Schema-faithful, hand-built.** `system dns list` is administrator-gated and empty on the dev machine, so it cannot be captured populated. Keys (`domainName`, `localhost`) pinned from the apple/container **1.0.0** binary's `CodingKeys` (`_domainName`/`domainName`, `localhost`) and the `system dns create --localhost <ip> <domain-name>` help surface. |

Decoders read only the subset of fields Capsule renders, so these fixtures
intentionally carry extra keys the decoders ignore — proving the subset-decode is
resilient to schema drift in unrelated fields.
