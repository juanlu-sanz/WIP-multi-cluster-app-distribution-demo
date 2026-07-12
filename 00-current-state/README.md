# Step 0 - Current State: Manual Deployment Without Cross-Cluster Mobility

## Description

This step reproduces the current operational reality: applications are deployed directly to individual clusters using `oc apply` or CI/CD pipelines that target a single cluster endpoint. There is no cross-cluster awareness - if an application needs to move from Cluster A to Cluster B (for upgrades, maintenance, or capacity), the team must manually reconfigure pipelines, recreate environments, and redirect DNS or load balancers. This is time-consuming, error-prone, and creates downtime windows.

## Prerequisites

- Two OpenShift 4.15+ clusters (referred to as `cluster-a` and `cluster-b` in this demo)
- `oc` CLI authenticated as cluster-admin on both clusters
- Contexts renamed as described in the [Cluster Setup](../README.md#cluster-setup) section

> **Note:** In a real-world scenario without contexts configured, teams would `oc login` to each cluster individually and re-authenticate every time they switch. This demo uses `--context` flags for convenience, but the manual, per-cluster nature of the workflow is the same.

## Steps to Reproduce

### 1. Deploy the sample application to Cluster A

- **What:** Deploy a simple stateless HTTP application directly to a single cluster using `oc apply`.
- **Why:** This represents the current workflow - each cluster is targeted individually, with no central control plane aware of where the application lives.

```bash
oc apply -f namespace.yaml --context cluster-a
oc apply -f deployment.yaml --context cluster-a
oc apply -f service.yaml --context cluster-a
oc apply -f route.yaml --context cluster-a
```

<details>
<summary>✅ Verify: Application running on Cluster A</summary>

```bash
oc get pods -n demo-app --context cluster-a
```

Expected output:

```
NAME                        READY   STATUS    RESTARTS   AGE
demo-app-6d4f5b7c8-x9k2m   1/1     Running   0          30s
```

```bash
oc get route demo-app -n demo-app --context cluster-a -o jsonpath='{.status.ingress[0].host}'
```

Expected output - a route URL pointing to Cluster A:

```
demo-app-demo-app.apps.cluster-a.example.com
```

```bash
curl -s http://$(oc get route demo-app -n demo-app --context cluster-a -o jsonpath='{.status.ingress[0].host}')
```

Expected output:

```json
{"message": "Hello from demo-app", "version": "1.0.0"}
```

</details>

---

### 2. Simulate the need to migrate to Cluster B

- **What:** Manually recreate the same application on a second cluster, simulating what happens when Cluster A needs maintenance or decommissioning.
- **Why:** This exposes the core problem - there is no mechanism to "move" an application. The team must repeat the entire deployment from scratch on the new cluster and then manually update every external dependency (DNS, load balancers, CI/CD pipelines).

Assume Cluster A needs maintenance. The application must move to Cluster B.

**What the team currently has to do:**

1. Target `cluster-b`
2. Manually recreate all resources
3. Update DNS / load balancer to point to the new cluster
4. Delete from the old cluster

```bash
oc apply -f namespace.yaml --context cluster-b
oc apply -f deployment.yaml --context cluster-b
oc apply -f service.yaml --context cluster-b
oc apply -f route.yaml --context cluster-b
```

<details>
<summary>✅ Verify: Application running on Cluster B</summary>

```bash
oc get pods -n demo-app --context cluster-b
```

Expected output:

```
NAME                        READY   STATUS    RESTARTS   AGE
demo-app-6d4f5b7c8-a3b4n   1/1     Running   0          25s
```

```bash
oc get route demo-app -n demo-app --context cluster-b -o jsonpath='{.status.ingress[0].host}'
```

Expected output - **a different route URL, pointing to Cluster B**:

```
demo-app-demo-app.apps.cluster-b.example.com
```

> **Note:** The URL has changed. Any external system, load balancer, or DNS entry that pointed to Cluster A must now be manually updated. This is where downtime occurs.

</details>

---

### 3. Clean up Cluster A (manual step)

- **What:** Manually delete all application resources from the old cluster after verifying the new one is working.
- **Why:** Without a control plane managing placement, cleanup is manual. If forgotten, orphaned resources waste compute and create confusion about where the application is actually running.

Go back to Cluster A and remove the old deployment:

```bash
oc delete -f route.yaml --context cluster-a
oc delete -f service.yaml --context cluster-a
oc delete -f deployment.yaml --context cluster-a
oc delete -f namespace.yaml --context cluster-a
```

<details>
<summary>✅ Verify: Application removed from Cluster A</summary>

```bash
oc get namespace demo-app --context cluster-a
```

Expected output:

```
Error from server (NotFound): namespaces "demo-app" not found
```

</details>

---

## Why This Is a Problem

| Problem | Impact |
|---|---|
| No single control plane for placement | Each cluster is managed independently - no way to declare "this app should run on Cluster B instead" |
| DNS / Route changes on every migration | External consumers must update their endpoints or wait for DNS propagation |
| No traffic shifting | Migration is all-or-nothing - no gradual rollover, no canary, no blue-green |
| Pipeline reconfiguration | CI/CD pipelines are hardcoded to a single cluster endpoint and must be manually updated |
| No disaster recovery posture | If a cluster goes down, there is no automated failover for stateless workloads |
| Manual process at scale | With 10+ clusters, this process becomes a significant operational burden |

The next steps in this demo address these problems:
- **[Step 1](../01-acm-workload-placement/)** introduces ACM to manage placement declaratively
- **[Step 2](../02-submariner-connectivity/)** deploys Submariner for encrypted cross-cloud connectivity between Azure and AWS
- **[Step 3](../03-service-mesh-traffic-management/)** adds Service Mesh for transparent traffic routing and zero-downtime failover
