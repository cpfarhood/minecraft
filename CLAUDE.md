# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Kubernetes manifests for Minecraft hosting infrastructure, managed with Kustomize and deployed to the `minecraft` namespace via Flux CD on a locally attached cluster. Supports multiple deployment strategies (Helm-based servers, Shulker/Agones clustering, Pterodactyl panel) that can be independently enabled via the root `kustomization.yaml`.

Changes are applied by committing and pushing to the repo — Flux automatically reconciles.

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
- `./pterodactyl` — Database infrastructure only (MariaDB clusters, DragonflyDB); panel/wings are commented out
- `./router/` — mc-router HelmRelease for hostname-based Minecraft routing via Cilium LBIPAM
- `./servers/` — Individual Minecraft server HelmReleases using `itzg/minecraft-server` chart v5.0.0

Inactive (commented out): `./proxy` (Velocity), `./shulker`, `./manual`

### Server HelmRelease Pattern

Each server in `servers/` is a Flux `HelmRelease` (API `helm.toolkit.fluxcd.io/v2`) following a consistent template:
- **Workload**: StatefulSet with `OnDelete` update strategy
- **Resources**: ~4 CPU, 10-14Gi memory requested, 12-18Gi limit
- **Storage**: 64Gi PVC per server
- **Probes**: Three-tier health checks using `mc-health` — startup (up to 40 min), readiness (2 min), liveness (5 min)
- **Scheduling**: Tolerates `farh.net/performance=high:NoSchedule` taint
- **Routing**: Service annotation `mc-router.itzg.me/externalServerName` for mc-router discovery
- **Availability**: PodDisruptionBudget with `minAvailable: 1`

When adding a new server, copy an existing HelmRelease, adjust values, and add the file to `servers/kustomization.yaml`.

### Networking Flow

External traffic → Cilium LBIPAM (71.150.236.210) → mc-router → backend servers (hostname-based routing via service annotations). The `${FQDN}` variable controls the public domain used in routing annotations and DNS records.

### Pterodactyl Infrastructure (`pterodactyl/`)

Uses operator CRDs, not raw manifests:
- `k8s.mariadb.com/v1alpha1` — `MariaDB`, `Database`, `User`, `Grant` resources (3-replica cluster with auto-failover)
- `dragonflydb.io/v1alpha1` — `Dragonfly` resource (Redis-compatible, 3 replicas)

Each database component has its own subdirectory with a kustomization. Secrets use `stringData` with `${PLACEHOLDER}` substitution and are labeled `k8s.mariadb.com/watch: ""` for operator-managed rotation.

### Webhook (`webhook/`)

A custom Python HTTP server that scales StatefulSets via the K8s API. Validates that target names match `.+-minecraft$`. Includes its own RBAC (ServiceAccount, Role, RoleBinding) scoped to `statefulsets/scale`.

### Shulker/Agones (Inactive)

`shulker/` contains ShulkerMC CRDs (`MinecraftCluster`, `ProxyFleet`, `MinecraftServerFleet`). `agones-operator/` and `shulker-operator/` are standalone Flux HelmReleases. Activation requires uncommenting in root kustomization and renaming the `.disabled` kustomization files.

## Environment Variables

All `${PLACEHOLDER}` values must be substituted before applying. Key categories:

- **Networking**: `${FQDN}`, `${PRIVATE_FQDN}`, various `*_FQDN` for services
- **Resource names**: `${CLUSTERNAME}`, `${PROXYFLEETNAME}`, `${SERVERFLEETNAME}`
- **Secrets**: `${PTERODACTYL_DB_ROOTPW}`, `${VELOCITY_FWD_SECRET}`, `${WEBHOOK_AUTH_TOKEN}`, etc.
- **Ops**: `${SERVER_OPS}` — comma-separated list used across server HelmReleases

## Required Cluster Operators

These must be installed separately before the CRDs in this repo will work:
- **Flux CD** — reconciles HelmRelease and HelmRepository resources
- **mariadb-operator** — manages MariaDB CRDs in `pterodactyl/db/` and `pterodactyl/userdata-db/`
- **DragonflyDB operator** — manages Dragonfly CRD in `pterodactyl/dragonflydb/`
- **ShulkerMC operator + Agones** — only needed if activating `shulker/`
- **external-dns** — resolves `external-dns.alpha.kubernetes.io/hostname` annotations to DNS records
- **Cilium** — provides LBIPAM and DSR forwarding for LoadBalancer services
