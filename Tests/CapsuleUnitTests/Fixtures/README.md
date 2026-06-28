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

Decoders read only the subset of fields Capsule renders, so these fixtures
intentionally carry extra keys the decoders ignore — proving the subset-decode is
resilient to schema drift in unrelated fields.
