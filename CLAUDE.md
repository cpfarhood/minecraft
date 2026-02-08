# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Kubernetes manifests for Minecraft hosting infrastructure, managed with Kustomize and deployed to the `minecraft` namespace via Flux CD on a locally attached cluster. Changes are applied by committing and pushing to the repo — Flux automatically reconciles.

## Commands

Preview rendered manifests locally:
```bash
kubectl kustomize .
```

Force Flux to reconcile immediately (instead of waiting for the interval):
```bash
flux reconcile kustomization minecraft -n minecraft
```

Check Flux reconciliation status:
```bash
flux get kustomizations -n minecraft
flux get helmreleases -n minecraft
```

Inspect live resources:
```bash
kubectl get pods -n minecraft
kubectl get helmreleases -n minecraft
```

## Architecture

### What's Currently Active

The root `kustomization.yaml` includes:
- `./databases` — Shared MariaDB cluster for core Minecraft gameplay data (3-replica, auto-failover)
- `./pterodactyl` — Database infrastructure only (MariaDB clusters, DragonflyDB); panel/wings/ctrlpanelgg are commented out
- `./proxy` — Velocity proxy HelmRelease (`minecraft-proxy` chart v3.10.0 from `farhoodliquor`)
- `./router/` — mc-router HelmRelease for hostname-based Minecraft routing via Cilium LBIPAM
- `./servers/` — Individual Minecraft server HelmReleases plus supporting infrastructure

Inactive (commented out): `./shulker` (ShulkerMC + Agones clustering)

### Server HelmRelease Pattern

Each server in `servers/` is a Flux `HelmRelease` (API `helm.toolkit.fluxcd.io/v2`) following a consistent template:
- **Chart**: `minecraft` from `farhoodliquor` (v5.2.0) or `itzg` (v5.0.0) HelmRepository
- **Workload**: StatefulSet with `OnDelete` update strategy
- **Resources**: ~4 CPU, 10-14Gi memory requested, 12-18Gi limit (varies by modpack weight)
- **Storage**: 32-64Gi PVC per server
- **Probes**: Three-tier health checks using `mc-health` — startup (up to 40 min for heavy modpacks), readiness (2 min), liveness (5 min)
- **Scheduling**: Tolerates `farh.net/performance=high:NoSchedule` taint
- **Routing**: Service annotation `mc-router.itzg.me/externalServerName` for mc-router discovery
- **Availability**: PodDisruptionBudget with `minAvailable: 1`
- **JVM**: G1GC with Aikar-style flags, heap sized to leave 2-4Gi native headroom within memory limit

When adding a new server, copy an existing HelmRelease, adjust values, and add the file to `servers/kustomization.yaml`.

### Supporting Infrastructure in `servers/`

Beyond the HelmReleases, `servers/` also contains:
- **PicoLimbo** — Lightweight limbo server for client fallback (Deployment + Service + ConfigMap)
- **FileBrowser** — Web file manager UI (StatefulSet + Service + Ingress)
- **Shared volumes** — 256Gi `ceph-filesystem` RWX PVC for cross-server shared data
- **Paper/Velocity config** — ConfigMap mounted by lobby server for Velocity forwarding

### Networking Flow

External traffic (port 25565) → Cilium LBIPAM (`${IP_ADDRESS}`) → mc-router → backend servers (hostname-based routing via service annotations). The `${FQDN}` variable controls the public domain used in routing annotations and DNS records.

The Velocity proxy sits between mc-router and backend servers when active, handling player auth and server switching. Backend servers configured in Velocity's `servers` block point back to `mc-router:25565` for routing, except always-on services (lobby, limbo) which are addressed directly.

### Pterodactyl Infrastructure (`pterodactyl/`)

Uses operator CRDs, not raw manifests:
- `k8s.mariadb.com/v1alpha1` — `MariaDB`, `Database`, `User`, `Grant` resources (3-replica cluster with auto-failover)
- `dragonflydb.io/v1alpha1` — `Dragonfly` resource (Redis-compatible, 3 replicas)

Each database component has its own subdirectory with a kustomization. Secrets use `stringData` with `${PLACEHOLDER}` substitution and are labeled `k8s.mariadb.com/watch: ""` for operator-managed rotation.

### Databases (`databases/`)

Shared MariaDB cluster (`minecraft-db`) for core gameplay data, separate from Pterodactyl's databases. Uses the same `k8s.mariadb.com/v1alpha1` operator CRDs: MariaDB, Database, User, Grant. 3-replica cluster with 16Gi storage and auto-failover.

### Shulker/Agones (Inactive)

`shulker/` contains ShulkerMC CRDs (`MinecraftCluster`, `ProxyFleet`, `MinecraftServerFleet`). `agones-operator/` and `shulker-operator/` are standalone Flux HelmReleases. Activation requires uncommenting in root kustomization and renaming the `.disabled` kustomization files.

## Environment Variables

All `${PLACEHOLDER}` values are substituted by the Flux Kustomization at reconciliation time. Key categories:

- **Networking**: `${FQDN}`, `${PRIVATE_FQDN}`, `${IP_ADDRESS}`, various `*_FQDN` for services
- **Resource names**: `${CLUSTERNAME}`, `${PROXYFLEETNAME}`, `${SERVERFLEETNAME}`
- **Secrets**: `${PLAY_DB_ROOTPW}`, `${PLAY_DB_USERPW}`, `${PTERODACTYL_DB_ROOTPW}`, `${VELOCITY_FWD_SECRET}`, `${PTERODACTYL_DRAGONFLYDB_PW}`, etc.
- **Ops**: `${SERVER_OPS}` — comma-separated list used across server HelmReleases

## HelmRepositories

Two HelmRepository sources are referenced by HelmReleases in this repo:
- **`farhoodliquor`** (namespace: `minecraft`) — Custom/private charts for mc-router, minecraft-proxy, and minecraft server (v5.2.0)
- **`itzg`** (namespace: `minecraft`) — Public `itzg/minecraft-server` chart (v5.0.0) at `https://itzg.me/helm/charts`

These HelmRepository resources must exist in the cluster. The `farhoodliquor` repository is defined externally.

## Required Cluster Operators

These must be installed separately before the CRDs in this repo will work:
- **Flux CD** — reconciles HelmRelease and HelmRepository resources
- **mariadb-operator** — manages MariaDB CRDs in `pterodactyl/db/`, `pterodactyl/userdata-db/`, and `databases/`
- **DragonflyDB operator** — manages Dragonfly CRD in `pterodactyl/dragonflydb/`
- **ShulkerMC operator + Agones** — only needed if activating `shulker/`
- **external-dns** — resolves `external-dns.alpha.kubernetes.io/hostname` annotations to DNS records
- **Cilium** — provides LBIPAM and DSR forwarding for LoadBalancer services
