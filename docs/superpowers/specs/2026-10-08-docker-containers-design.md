# Docker containers as servers

## Goal

Ports published by running containers (for example `m2a-web-ui` on `:3000`) appear as server rows. Each row shows which container owns the port, and Stop and Restart act on the container. This works with any runtime the `docker` CLI talks to (Docker Desktop, OrbStack, Colima, Rancher). Containers are never cleaned up automatically, and an Integrations toggle can hide them.

## Background

On macOS, Docker Desktop's published ports are held by `com.docker.backend` inside `/Applications/Docker.app`. `ScanEngine` drops these sockets for two reasons: the process is not in the allowlist, and executables inside `.app/Contents/` are skipped. Allowlisting the process is not safe, because Stop would SIGTERM Docker's backend and take every container down with it.

## Design

### Engine: `Engine/DockerScanner.swift`

- Runs `docker ps --no-trunc --format '{{json .}}'` with a 2 second timeout, so a hung daemon cannot stall the scan queue.
- Finds the CLI at the first existing path among `/usr/local/bin/docker`, `/opt/homebrew/bin/docker`, `~/.orbstack/bin/docker` and `~/.docker/bin/docker`. An app launched from Finder has no shell `PATH`.
- Parses each container's `ID`, `Names`, `Image`, `Labels` and `Ports`. Host ports come from TCP entries of the form `<addr>:<host>-><container>/tcp`, including ranges such as `0.0.0.0:3000-3001->3000-3001/tcp`. Duplicate IPv4 and IPv6 entries collapse into one port, and the bound addresses are kept.
- Reads the labels `com.docker.compose.project`, `com.docker.compose.service` and `com.docker.compose.project.working_dir`.
- If docker is missing, the daemon is down, the call times out or the output can't be parsed, the result is an empty list and the scan carries on as before.

### Stats: `DockerScanner` background sampler

- A background loop on its own queue runs `docker stats --no-stream --format '{{json .}}'` back to back, with a 5 second timeout per call. Each call takes about 2 seconds because docker samples CPU over an interval, so it runs off the scan queue and the scan reads the most recent cached values.
- From each entry it parses `ID`, `MemUsage` (the part before ` / `, with units B, KiB, MiB, GiB, kB, MB, GB) and `CPUPerc`.
- The loop starts when the first scan sees running containers and stops when none are left or `showDocker` is off. A failed call leaves the cache empty, and container rows then fall back to 0.
- Values lag by at most one sample (about 2 seconds), which is close to the default scan interval.

### Model

`Server` gains `container: DockerContainer?` with `id`, `name`, `image`, `composeProject`, `composeService`.

### Scan

- `ScanEngine.scan` takes the container list as an input next to sockets and processes, so tests can supply snapshot data.
- For every published host port inside `minPort...maxPort`, it adds one `Server`:
  - `pid` and `rootPid` are 0, and `processes` and `processStarts` are empty, so the signal-based stop path has nothing to signal.
  - `processName` is `docker`, `command` is the image, and `cwd` is the Compose working directory, or nil if there is none. The existing `ProjectResolver` then supplies the project name, branch and editor actions.
  - `memory` and `cpu` come from the cached stats for that container, or 0 before the first sample. When a container publishes several ports, each of its rows shows the container's full memory, the same way two ports on one process tree each show that tree's memory. History and last-active tracking use the same key scheme with the container id in place of the root pid. As a result the memory chart, the over-threshold alert, leak warnings and the attention status all work for containers.
- Any lsof listener on a port a container publishes is skipped. This covers `com.docker.backend`, `docker-proxy` and the OrbStack helpers.
- `ScanConfig.showDocker` comes from `Preferences.showDocker` (default on). When it is off, no container rows are added and the lsof rows are not touched.

### Actions

- `ProcessControl.stop` and `restart` branch on `server.container` and run `docker stop <id>` or `docker restart <id>` off the main thread, then call the completion handler.
- Restart is enabled for container rows in `ServerDetailView` and the `wtp` terminal UI.
- `ServerMonitor.cleanUpReason` returns nil for container rows, so Clean up never suggests or auto-stops a container.

### UI

- The row title is the container name, with a "Docker" tag.
- The detail view shows memory and CPU like any server, with the image and Compose project/service in place of the process tree.
- New strings are localized in all eight languages.

### Out of scope (v1)

- Containers that are not running, and UDP ports.

## Testing

- Unit tests (`ScanEngineTests`, plus a new `DockerScannerTests`):
  - Parsing `docker stats` JSON lines and memory units.
  - Parsing `docker ps` JSON lines, port strings (IPv4/IPv6 duplicates, ranges, UDP ignored, unpublished ports ignored) and Compose labels.
  - Container rows replace the lsof row on the same port, honour the port range, and are absent when `showDocker` is off.
  - `cleanUpReason` is nil for container rows.
  - Container rows take memory and CPU from the stats cache, and grow a history across scans.
- Manual check against the running Docker Desktop containers: rows appear with memory matching `docker stats`, Stop and Restart work, and Docker Desktop itself stays up.

## Marketing site and docs (AGENTS.md)

- The demo gains a deterministic Docker container row with simulated Stop and Restart (`servers.ts`, `App.tsx`, `icons.tsx` if a tag is needed, `landing.module.css`).
- `Copy.tsx`, `README.md` and `content/whattheport.md` mention Docker support. The Docker line in `content/guides/eaddrinuse-address-already-in-use.md` is updated.
- Affected screenshots in `docs/images/` are refreshed.
- Verified in a browser on desktop and mobile, with `npm run build` passing and review screenshots saved in `.context/`.
