# Step 3 - Solution: Service Mesh for Traffic Management

## Summary

This step adds OpenShift Service Mesh 3.0 (Istio ambient mode) on top of the ACM placement from [Step 1](../01-acm-workload-placement/) and the Submariner connectivity from [Step 2](../02-submariner-connectivity/). With Service Mesh, traffic routing is decoupled from the underlying cluster and cloud provider - consumers hit a stable service endpoint, and the mesh transparently routes traffic to whichever cluster is currently running the workload, whether it's on Azure or AWS. This enables zero-downtime migrations, blue-green failover, canary traffic shifting, and zero-trust mutual TLS between services - all without changing DNS records or load balancers.

## Prerequisites

- ACM Hub cluster with workload placement from [Step 1](../01-acm-workload-placement/) fully operational
- Submariner cross-cloud connectivity from [Step 2](../02-submariner-connectivity/) verified and working
- At least two managed clusters (`cluster-a` on Azure, `cluster-b` on AWS) joined to the Hub
- OpenShift Service Mesh 3.0 Operator installed on all participating clusters (Hub + managed)
- `oc` CLI authenticated as cluster-admin on the Hub cluster
- Contexts renamed as described in the [Cluster Setup](../README.md#cluster-setup) section

> **Note:** Cross-cluster network connectivity is provided by Submariner (Step 2). The `$REMOTE_INGRESS_IP` used in the ServiceEntry can be an internal cluster IP because Submariner's IPsec tunnel makes it reachable across Azure and AWS.

> **Note:** Service Mesh resources are applied directly on the managed clusters. Every `oc` command specifies `--context cluster-a` or `--context cluster-b` explicitly.

## Steps to Apply

### 1. Install the Istio control plane in ambient mode

- **What:** Deploy the Istio control plane using the ambient profile, which installs a ztunnel DaemonSet on every node for Layer 4 traffic interception.
- **Why:** Ambient mode replaces the traditional sidecar model (one envoy container per pod) with a per-node proxy. This reduces resource overhead and simplifies adoption - existing workloads join the mesh without restarting or injecting sidecars. The ztunnel handles mTLS and Layer 4 routing transparently.

```bash
oc apply -f istio.yaml --context cluster-a
oc apply -f istio.yaml --context cluster-b
```

<details>
<summary>✅ Verify: Istio control plane running</summary>

```bash
oc get istio default -n istio-system --context cluster-a
```

Expected output:

```
NAME      REVISIONS   READY   IN USE   ACTIVE REVISION   STATUS   AGE
default   1           1       1        default            Healthy  60s
```

```bash
oc get daemonset ztunnel -n istio-system --context cluster-a
```

Expected output:

```
NAME      DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   AGE
ztunnel   3         3         3       3             3           45s
```

</details>

---

### 2. Enroll the application namespace into the mesh

- **What:** Label the `demo-app` namespace with `istio.io/dataplane-mode=ambient` on both managed clusters.
- **Why:** In ambient mode, the mesh is opt-in at the namespace level. Adding this label tells the ztunnel DaemonSet to intercept traffic for all pods in this namespace - enabling mTLS encryption and Layer 4 policy enforcement without any changes to the application itself.

```bash
oc label namespace demo-app istio.io/dataplane-mode=ambient --context cluster-a --overwrite
oc label namespace demo-app istio.io/dataplane-mode=ambient --context cluster-b --overwrite
```

<details>
<summary>✅ Verify: Namespace enrolled in the mesh</summary>

```bash
oc get namespace demo-app --show-labels --context cluster-a | grep istio
```

Expected output contains:

```
istio.io/dataplane-mode=ambient
```

</details>

---

### 3. Deploy the waypoint proxy for Layer 7 capabilities

- **What:** Deploy a waypoint Gateway resource in the `demo-app` namespace on both clusters.
- **Why:** Ambient mode only provides Layer 4 (TCP) traffic management by default. For HTTP-level routing - which we need for weighted traffic splits, canary deployments, and header-based matching - a waypoint proxy must be deployed. The waypoint is a lightweight envoy instance that handles Layer 7 for the specific namespace, without requiring sidecars in every pod.

```bash
oc apply -f waypoint.yaml --context cluster-a
oc apply -f waypoint.yaml --context cluster-b
```

<details>
<summary>✅ Verify: Waypoint proxy running</summary>

```bash
oc get gateway demo-app-waypoint -n demo-app --context cluster-a
```

Expected output:

```
NAME                CLASS   ADDRESS         PROGRAMMED   AGE
demo-app-waypoint   istio   10.96.xxx.xxx   True         30s
```

</details>

---

### 4. Apply the cross-cluster ServiceEntry

- **What:** Create a ServiceEntry that registers the remote cluster's demo-app as a mesh-internal service accessible via `demo-app.demo-app.global`.
- **Why:** By default, each cluster's mesh only knows about local services. The ServiceEntry tells the mesh "there is a service called `demo-app.demo-app.global` that can be reached locally and also at the remote cluster's ingress." This is what enables cross-cluster traffic routing - without it, the VirtualService would have nowhere to route traffic.

```bash
envsubst < service-entry.yaml | oc apply --context cluster-a -f -
envsubst < service-entry.yaml | oc apply --context cluster-b -f -
```

<details>
<summary>✅ Verify: ServiceEntry created</summary>

```bash
oc get serviceentry -n demo-app --context cluster-a
```

Expected output:

```
NAME                    HOSTS                           LOCATION      RESOLUTION   AGE
demo-app-cross-cluster  ["demo-app.demo-app.global"]    MESH_INTERNAL DNS          15s
```

</details>

---

### 5. Apply the VirtualService for traffic routing

- **What:** Create a VirtualService that controls how traffic to `demo-app.demo-app.global` is distributed. Start with 100% to cluster-a.
- **Why:** The VirtualService is the traffic control layer. It decouples the service consumers from the physical cluster - they always call `demo-app.demo-app.global`, and the VirtualService decides which cluster actually serves the request. This is what eliminates DNS changes on migration: the endpoint stays the same, only the routing weights change.

```bash
oc apply -f virtualservice-100-cluster-a.yaml --context cluster-a
```

<details>
<summary>✅ Verify: VirtualService active</summary>

```bash
oc get virtualservice demo-app-routing -n demo-app --context cluster-a
```

Expected output:

```
NAME               GATEWAYS   HOSTS                        AGE
demo-app-routing              ["demo-app.demo-app.global"] 10s
```

</details>

---

### 6. Apply the DestinationRule for cluster-specific subsets

- **What:** Create a DestinationRule that defines named subsets (`cluster-a`, `cluster-b`) based on endpoint labels, with mTLS enabled.
- **Why:** The VirtualService routes to named subsets - this DestinationRule maps those names to actual endpoints. It also enforces `ISTIO_MUTUAL` TLS, ensuring all cross-cluster traffic is encrypted and mutually authenticated. Without this, the VirtualService has no way to distinguish between cluster-a and cluster-b endpoints.

```bash
oc apply -f destination-rule.yaml --context cluster-a
```

<details>
<summary>✅ Verify: DestinationRule created</summary>

```bash
oc get destinationrule demo-app-dr -n demo-app --context cluster-a
```

Expected output:

```
NAME          HOST                       AGE
demo-app-dr   demo-app.demo-app.global   10s
```

</details>

---

### 7. Perform a blue-green migration

- **What:** Switch 100% of traffic from cluster-a to cluster-b by applying an updated VirtualService.
- **Why:** This is the full migration, combined with ACM placement from Step 1. ACM has already deployed the workload to cluster-b - now we shift all traffic there in one step. Because the consumers still call `demo-app.demo-app.global`, they experience zero downtime and no URL change. This is the blue-green switch that was impossible in Step 0.

```bash
oc apply -f virtualservice-100-cluster-b.yaml --context cluster-a
```

<details>
<summary>✅ Verify: Traffic now routed to Cluster B</summary>

```bash
oc get virtualservice demo-app-routing -n demo-app --context cluster-a -o yaml | grep -A10 "route:"
```

Expected output:

```yaml
    route:
      - destination:
          host: demo-app.demo-app.global
          subset: cluster-b
        weight: 100
```

Test end-to-end connectivity:

```bash
curl -s http://demo-app.demo-app.global
```

Expected output (from cluster-b):

```json
{"message": "Hello from demo-app", "version": "1.0.0"}
```

</details>

---

### 8. (Optional) Canary traffic shifting

- **What:** Instead of an all-at-once switch, apply a VirtualService that sends 90% of traffic to cluster-a and 10% to cluster-b.
- **Why:** Canary shifting lets you validate the new cluster with real production traffic before committing to a full migration. If something goes wrong on cluster-b, only 10% of users are affected and you can instantly roll back by reapplying the 100%-cluster-a VirtualService.

```bash
oc apply -f virtualservice-canary-90-10.yaml --context cluster-a
```

<details>
<summary>✅ Verify: Canary traffic split active</summary>

```bash
oc get virtualservice demo-app-routing -n demo-app --context cluster-a -o yaml | grep -A15 "route:"
```

Expected output:

```yaml
    route:
      - destination:
          host: demo-app.demo-app.global
          subset: cluster-a
        weight: 90
      - destination:
          host: demo-app.demo-app.global
          subset: cluster-b
        weight: 10
```

</details>

---

### 9. Apply the PeerAuthentication for zero-trust mTLS

- **What:** Enforce STRICT mutual TLS for the `demo-app` namespace on both clusters, requiring all communication to present a valid mesh identity.
- **Why:** This implements zero-trust networking at the pod level. No application can communicate with `demo-app` unless it is part of the mesh and has a valid SPIFFE identity. This replaces namespace-level network policies with identity-based authentication - a more granular security model that works consistently across clusters.

```bash
oc apply -f peer-authentication.yaml --context cluster-a
oc apply -f peer-authentication.yaml --context cluster-b
```

<details>
<summary>✅ Verify: mTLS enforced</summary>

```bash
oc get peerauthentication -n demo-app --context cluster-a
```

Expected output:

```
NAME               MODE     AGE
demo-app-strict    STRICT   10s
```

To confirm mTLS is active, attempt a request from a pod that is not part of the mesh:

```bash
oc run test-pod --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  -n default --context cluster-a --restart=Never --rm -i -- \
  curl -s http://demo-app.demo-app.svc.cluster.local:8080
```

Expected output (connection refused - non-mesh pod cannot reach the service):

```
curl: (56) Recv failure: Connection reset by peer
```

</details>

---

## What This Solves (Combined with Steps 1 and 2)

| Problem from Step 0 | How ACM + Submariner + Service Mesh Solve It |
|---|---|
| DNS/Route changes on every migration | Service Mesh provides a stable virtual endpoint - consumers never see the cluster or cloud switch |
| No traffic shifting | VirtualService enables canary, blue-green, and weighted traffic splits across Azure and AWS |
| All-or-nothing migration | Gradual traffic shifting allows validation before committing to the new cloud/cluster |
| No zero-trust networking | PeerAuthentication enforces strict mTLS - services communicate only with explicitly allowed peers, even across clouds |
| External LB reconfiguration | Service Mesh handles routing internally over the Submariner tunnel - no cloud-specific LB changes needed for workload moves |

## Official Documentation

- [OpenShift Service Mesh 3.0 Overview](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.0/html/about_red_hat_openshift_service_mesh/about-ossm)
- [Installing the Service Mesh Operator](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.0/html/installing/ossm-installing)
- [Istio Ambient Mode](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.0/html/about_red_hat_openshift_service_mesh/ossm-about-ambient)
- [Traffic Management (VirtualService, DestinationRule)](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.0/html/traffic_management/ossm-traffic-management)
- [Security (PeerAuthentication, mTLS)](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.0/html/security/ossm-security)
- [Multi-cluster Mesh](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.0/html/installing/ossm-multicluster)

## Alternatives Considered

| Approach | Notes |
|---|---|
| Service Mesh (this solution) | Full L4/L7 traffic management, mTLS, canary, blue-green - all declarative. Requires mesh installation on all clusters. |
| F5 Global Traffic Manager (GTM) | External LB can route traffic between clusters, but requires manual or API-driven configuration changes. Not part of the Red Hat stack. |
| Azure Traffic Manager / Front Door | Cloud-native option for Azure workloads. Adds latency for health probes and limits L7 capabilities compared to Service Mesh. |
| DNS-based failover (Route53 / external DNS) | Simple but slow (DNS TTL propagation) and lacks fine-grained traffic control (no canary, no weighted splits). |
