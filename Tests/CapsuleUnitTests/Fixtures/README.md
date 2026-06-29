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
| `dns-ls.json` | **Real capture** — `container system dns list --format json` (CLI v1.0.0) after `sudo container system dns create test`. The populated list is an array of **bare domain-name strings** (`["test"]`) — NOT objects, and it never echoes the create-time `--localhost` IP. (Supersedes the earlier hand-built object guess, which made the DNS pane show nothing because the real string array failed object-decode.) |
| `containers-with-mounts.json` | **Real capture** — `container list -a --format json` of a throwaway container (`capsule-fx`) created with `-v capsule-fx-vol:/data --network capsule-fx-net`, filtered to that one container; throwaway volume/network/container deleted immediately after. Pins the M8 attachment keys (§5.5): the volume **name** is at `configuration.mounts[].type.volume.name` (NOT `mounts[].source`, which is the host path to `volume.img`); the network name is at `configuration.networks[].network`. |

Decoders read only the subset of fields Capsule renders, so these fixtures
intentionally carry extra keys the decoders ignore — proving the subset-decode is
resilient to schema drift in unrelated fields.
