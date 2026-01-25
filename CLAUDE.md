# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains Kubernetes manifests for deploying Minecraft infrastructure using Kustomize. It supports multiple deployment strategies including Shulker/Agones-based clusters and Pterodactyl game server panels.

## Commands

Apply manifests:
```bash
kubectl apply -k .
```

Preview manifests before applying:
```bash
kubectl kustomize .
```

Apply a specific component:
```bash
kubectl apply -k ./shulker
kubectl apply -k ./pterodactyl
```

## Architecture

### Deployment Strategies

The root `kustomization.yaml` selectively includes different deployment approaches:

- **shulker/** - Shulker operator with Agones for auto-scaling Minecraft clusters (currently active)
- **pterodactyl/** - Pterodactyl panel for game server management (currently active)
- **itzg/** - itzg Helm charts via Flux HelmRelease (inactive)
- **farhoodliquor/** - Custom fork of itzg charts (inactive)
- **manual/** - Manually-managed StatefulSets (inactive)

### Shulker Components

Uses ShulkerMC CRDs (`shulkermc.io/v1alpha1`):
- `MinecraftCluster` - Top-level cluster definition
- `ProxyFleet` - Velocity proxy with LoadBalancer service and external-dns
- `MinecraftServerFleet` - Paper server fleet with lobby tags

Environment variables like `${CLUSTERNAME}`, `${PROXYFLEETNAME}`, `${FQDN}` must be substituted before applying.

### Pterodactyl Components

- **db/** - MariaDB cluster (3 replicas, auto-failover) using mariadb-operator CRDs
- **userdata-db/** - Separate MariaDB instance for user data
- **dragonflydb/** - DragonflyDB (Redis-compatible) cluster for caching
- **panel/** - Pterodactyl Panel deployment with PVCs for var, nginx, logs
- **ctrlpanelgg/** - Alternative control panel (inactive)

### Key Operators/CRDs Required

- `shulkermc.io/v1alpha1` - ShulkerMC operator
- `k8s.mariadb.com/v1alpha1` - MariaDB operator
- `dragonflydb.io/v1alpha1` - DragonflyDB operator
- `helm.toolkit.fluxcd.io/v2beta1` - Flux CD (for Helm-based deployments)
