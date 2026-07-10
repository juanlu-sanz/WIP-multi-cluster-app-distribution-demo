# Demo: Multi-Cluster Application Distribution

## Summary

This demo demonstrates how to achieve seamless application mobility across multiple OpenShift clusters. It starts by reproducing the current pain point - manual, disconnected deployments that require pipeline reconfiguration for every cluster change - and then progressively introduces Red Hat Advanced Cluster Management (ACM) for declarative workload placement and OpenShift Service Mesh for transparent cross-cluster traffic management and failover.

## Environment

| Item | Value |
|---|---|
| OpenShift version | 4.15+ |
| ACM version | 2.10+ |
| OpenShift Service Mesh | 3.0+ (Istio ambient mode) |
| OpenShift GitOps (Argo CD) | 1.12+ |
| Cloud provider / platform | Any (AWS, Azure, bare metal, on-premises) |

## Repository Structure

| Folder | Purpose |
|---|---|
| [`00-current-state/`](./00-current-state/) | Simulates the current manual deployment workflow - no cross-cluster awareness, no automated placement |
| [`01-acm-workload-placement/`](./01-acm-workload-placement/) | Uses ACM to manage workload placement and migrate applications between clusters declaratively |
| [`02-service-mesh-traffic-management/`](./02-service-mesh-traffic-management/) | Uses OpenShift Service Mesh for transparent traffic routing, blue-green failover, and zero-trust networking across clusters |

## Quick Start

Start with [`00-current-state/`](./00-current-state/) to understand the current problem, then proceed to [`01-acm-workload-placement/`](./01-acm-workload-placement/) to see how ACM solves the placement challenge, and finally [`02-service-mesh-traffic-management/`](./02-service-mesh-traffic-management/) to add transparent traffic management on top.

## Prerequisites

- An ACM Hub cluster with at least two managed clusters joined
- `oc` CLI authenticated as cluster-admin on the Hub
- Cluster admin access to both managed clusters
- OpenShift GitOps Operator installed on the Hub (for step 01+)
- OpenShift Service Mesh 3.0 Operator installed on all clusters (for step 02)

## Cluster Setup

Before starting, log in to all three clusters, rename the contexts, and export the workshop variables. This only needs to be done once per terminal session.

### 1. Export workshop variables

Fill in your values and export them. These variables are referenced by YAML files in this repo and substituted at apply time via `envsubst`.

```bash
export HUB_API_URL="https://api.hub.example.com:6443"
export CLUSTER_A_API_URL="https://api.cluster-a.example.com:6443"
export CLUSTER_B_API_URL="https://api.cluster-b.example.com:6443"
export GIT_ORG="your-github-org"
export REMOTE_INGRESS_IP="10.0.0.1"
```

| Variable | Used in | Description |
|---|---|---|
| `HUB_API_URL` | This README (login) | API server URL for the ACM Hub cluster |
| `CLUSTER_A_API_URL` | This README (login) | API server URL for the first managed cluster |
| `CLUSTER_B_API_URL` | This README (login) | API server URL for the second managed cluster |
| `GIT_ORG` | [`01-acm-workload-placement/channel.yaml`](./01-acm-workload-placement/channel.yaml) | GitHub org/user for the ACM Channel Git repository |
| `REMOTE_INGRESS_IP` | [`02-service-mesh-traffic-management/service-entry.yaml`](./02-service-mesh-traffic-management/service-entry.yaml) | Ingress gateway IP of the peer cluster for cross-cluster mesh routing |

### 2. Log in to each cluster

```bash
oc login --server=$HUB_API_URL
oc login --server=$CLUSTER_A_API_URL
oc login --server=$CLUSTER_B_API_URL
```

### 3. Rename the contexts

The default context names are long and auto-generated. Rename them to `hub`, `cluster-a`, and `cluster-b`:

```bash
oc config rename-context <HUB_CONTEXT_NAME> hub
oc config rename-context <CLUSTER_A_CONTEXT_NAME> cluster-a
oc config rename-context <CLUSTER_B_CONTEXT_NAME> cluster-b
```

> **Tip:** Run `oc config get-contexts` after each login to see the auto-generated context name and use it in the rename command.

### 4. Verify

```bash
oc config get-contexts
```

Expected output:

```
CURRENT   NAME        CLUSTER                    AUTHINFO
          hub         api-hub:6443               admin/api-hub:6443
          cluster-a   api-cluster-a:6443         admin/api-cluster-a:6443
*         cluster-b   api-cluster-b:6443         admin/api-cluster-b:6443
```

From this point on, every `oc` command in the workshop uses `--context hub`, `--context cluster-a`, or `--context cluster-b` explicitly, so you never need to switch your active context. YAML files with `${VARIABLE}` placeholders are piped through `envsubst` before applying.
