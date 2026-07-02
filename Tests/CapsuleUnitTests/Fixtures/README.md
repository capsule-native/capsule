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
| `hub-search-repositories.json` | **Real capture** — `GET https://hub.docker.com/v2/search/repositories/?query=nginx&page=1&page_size=25` (Docker Hub v2 API, 2026-07-02), trimmed to the first 4 results but keeping the real top-level shape (`count` 288701, real `next` URL, `previous` `""`). Includes the official `nginx` row (`is_official` true, `pull_count` 13114222271) and namespaced non-official rows. |
| `hub-search-repositories-empty.json` | **Real capture** — Docker Hub v2 search for a query with zero hits (2026-07-02), verbatim: `count` 0, `next`/`previous` empty strings, `results` `[]`. |
| `hub-repository-tags.json` | **Real capture** — `GET https://hub.docker.com/v2/repositories/library/nginx/tags/?page_size=25&page=1` (Docker Hub v2 API, 2026-07-02), trimmed to the first 2 results but keeping each row's full real structure — nested `images` arrays and other unknown fields prove the subset-decode ignores them — plus the fractional-seconds `last_updated`, `full_size`, `digest`, and top-level `count`/`next` (URL)/`previous` (JSON `null`). |
| `containers-with-mounts.json` | **Real capture** — `container list -a --format json` of a throwaway container (`capsule-fx`) created with `-v capsule-fx-vol:/data --network capsule-fx-net`, filtered to that one container; throwaway volume/network/container deleted immediately after. Pins the M8 attachment keys (§5.5): the volume **name** is at `configuration.mounts[].type.volume.name` (NOT `mounts[].source`, which is the host path to `volume.img`); the network name is at `configuration.networks[].network`. |

Decoders read only the subset of fields Capsule renders, so these fixtures
intentionally carry extra keys the decoders ignore — proving the subset-decode is
resilient to schema drift in unrelated fields.
