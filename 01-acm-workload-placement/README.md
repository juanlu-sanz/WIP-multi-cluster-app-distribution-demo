# Step 1 - Solution: ACM Workload Placement

## Summary

This step introduces Red Hat Advanced Cluster Management (ACM) to manage workload placement declaratively. Instead of manually deploying to individual clusters and reconfiguring pipelines, we define a `Placement` rule in YAML that tells ACM where the application should run. To migrate the application from one cluster to another, we simply update the placement rule - ACM handles the rest. Combined with OpenShift GitOps (Argo CD), the entire desired state lives in Git, providing both a single control plane for multi-cluster deployments and a foundation for disaster recovery.

## Prerequisites

- ACM Hub cluster (OpenShift 4.15+) with ACM 2.10+ installed
- At least two managed clusters joined to the Hub (`cluster-a` and `cluster-b`)
- OpenShift GitOps Operator installed on the Hub
- `oc` CLI authenticated as cluster-admin on the Hub cluster
- Contexts renamed as described in the [Cluster Setup](../README.md#cluster-setup) section
- Managed clusters labeled appropriately (see step 1 below)

> **Note:** All commands in this step run on the Hub cluster (`--context hub`) unless a `--context cluster-a` or `--context cluster-b` flag specifies otherwise.

## Steps to Apply

### 1. Label your managed clusters

- **What:** Assign region and environment labels to each managed cluster registered in ACM.
- **Why:** ACM Placement rules select target clusters based on labels. By labeling clusters with `region` and `environment`, we can write placement rules like "deploy to the cluster in west-europe" - and later change to "deploy to north-europe" with a single YAML edit.

```bash
oc label managedcluster cluster-a region=west-europe environment=production --overwrite --context hub
oc label managedcluster cluster-b region=north-europe environment=production --overwrite --context hub
```

<details>
<summary>✅ Verify: Cluster labels applied</summary>

```bash
oc get managedclusters --show-labels --context hub
```

Expected output:

```
NAME        HUB ACCEPTED   MANAGED CLUSTER URLS                  JOINED   AVAILABLE   AGE   LABELS
cluster-a   true           https://api.cluster-a.example.com     True     True        10d   environment=production,region=west-europe,...
cluster-b   true           https://api.cluster-b.example.com     True     True        10d   environment=production,region=north-europe,...
```

</details>

---

### 2. Create the ManagedClusterSet

- **What:** Group the managed clusters into a `ManagedClusterSet` and bind it to the ACM application namespace.
- **Why:** A ManagedClusterSet defines the pool of clusters that Placement rules can select from. The binding allows resources in the `demo-app-acm` namespace to reference this set. Without the binding, the Placement has no clusters to choose from.

```bash
oc apply -f managedclusterset.yaml --context hub
oc apply -f managedclusterset-binding.yaml --context hub
```

<details>
<summary>✅ Verify: ManagedClusterSet created and bound</summary>

```bash
oc get managedclusterset production-clusters --context hub
```

Expected output:

```
NAME                   EMPTY   AGE
production-clusters    False   10s
```

```bash
oc get managedclustersetbinding -n demo-app-acm --context hub
```

Expected output:

```
NAME                   CLUSTERSET            AGE
production-clusters    production-clusters   10s
```

</details>

---

### 3. Create the Namespace, Channel, Placement, and Subscription

- **What:** Deploy the ACM application lifecycle resources: a Namespace for ACM control objects, a Channel pointing to the Git repo with the app manifests, a Placement rule targeting `cluster-a`, and a Subscription that ties them together.
- **Why:** This is the core of ACM application deployment. The Channel tells ACM where the manifests live (Git). The Placement tells ACM which cluster to deploy to. The Subscription connects them - "deploy the manifests from this Channel to whichever cluster the Placement selects." From this point on, placement is declarative: change the Placement YAML, and ACM moves the application.

```bash
oc apply -f namespace.yaml --context hub
envsubst < channel.yaml | oc apply --context hub -f -
oc apply -f placement-cluster-a.yaml --context hub
oc apply -f subscription.yaml --context hub
```

<details>
<summary>✅ Verify: Application deployed to Cluster A via ACM</summary>

Check the Subscription status on the Hub:

```bash
oc get subscription demo-app-subscription -n demo-app-acm --context hub
```

Expected output:

```
NAME                     STATUS       AGE
demo-app-subscription    Propagated   30s
```

Check that ACM placed the workload on `cluster-a`:

```bash
oc get placementdecision -n demo-app-acm --context hub -o yaml | grep -A5 "decisions:"
```

Expected output:

```yaml
  decisions:
    - clusterName: cluster-a
      reason: ""
```

Verify the pods are running on Cluster A:

```bash
oc get pods -n demo-app --context cluster-a
```

Expected output:

```
NAME                        READY   STATUS    RESTARTS   AGE
demo-app-6d4f5b7c8-x9k2m   1/1     Running   0          45s
demo-app-6d4f5b7c8-r7t3p   1/1     Running   0          45s
```

</details>

---

### 4. Migrate the application to Cluster B

- **What:** Replace the Placement rule with one that targets `cluster-b` (north-europe) instead of `cluster-a` (west-europe).
- **Why:** This is the migration itself - and the key difference from Step 0. Instead of logging into two clusters, re-applying manifests, updating DNS, and cleaning up the old deployment, we change a single YAML file. ACM deploys the application to cluster-b and removes it from cluster-a automatically.

```bash
oc apply -f placement-cluster-b.yaml --context hub
```

This replaces the previous Placement that targeted `cluster-a` with one that targets `cluster-b`. ACM will:
1. Deploy the application to `cluster-b`
2. Remove it from `cluster-a`

<details>
<summary>✅ Verify: Application migrated to Cluster B</summary>

Check the updated PlacementDecision:

```bash
oc get placementdecision -n demo-app-acm --context hub -o yaml | grep -A5 "decisions:"
```

Expected output:

```yaml
  decisions:
    - clusterName: cluster-b
      reason: ""
```

Verify the pods are now running on Cluster B:

```bash
oc get pods -n demo-app --context cluster-b
```

Expected output:

```
NAME                        READY   STATUS    RESTARTS   AGE
demo-app-6d4f5b7c8-k8m2n   1/1     Running   0          30s
demo-app-6d4f5b7c8-p4q7r   1/1     Running   0          30s
```

Verify the pods are gone from Cluster A:

```bash
oc get pods -n demo-app --context cluster-a
```

Expected output:

```
No resources found in demo-app namespace.
```

</details>

<details>
<summary>✅ Verify: Route accessible on Cluster B</summary>

```bash
curl -sk https://$(oc get route demo-app -n demo-app --context cluster-b -o jsonpath='{.status.ingress[0].host}')
```

Expected output:

```json
{"message": "Hello from demo-app", "version": "1.0.0"}
```

</details>

---

## What This Solves (Compared to Step 0)

| Problem from Step 0 | How ACM Solves It |
|---|---|
| No single control plane | ACM Hub manages all clusters from one place |
| Manual pipeline reconfiguration | Placement rules are YAML - change the label selector, ACM handles the rest |
| No disaster recovery posture | All placement rules live in Git - rebuild from Git if the Hub goes down |
| Manual process at scale | One `Placement` change moves the app across any number of clusters |

## What This Does NOT Solve (Yet)

| Remaining Problem | Addressed In |
|---|---|
| DNS/Route changes on migration | [Step 2 - Service Mesh](../02-service-mesh-traffic-management/) |
| No gradual traffic shifting | [Step 2 - Service Mesh](../02-service-mesh-traffic-management/) |
| Zero-trust inter-service communication | [Step 2 - Service Mesh](../02-service-mesh-traffic-management/) |

## Official Documentation

- [ACM Application Lifecycle Management](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.11/html/applications/managing-applications)
- [Placement API Overview](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.11/html/clusters/cluster_mce_overview#placement-overview)
- [ManagedClusterSets](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.11/html/clusters/cluster_mce_overview#managedclustersets-intro)
- [Subscriptions](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.11/html/applications/managing-applications#managing-subscriptions)
- [OpenShift GitOps Operator](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.14/html/understanding_openshift_gitops/index)

## Alternatives Considered

| Approach | Notes |
|---|---|
| ACM Placement (this solution) | Declarative, GitOps-native, single control plane for placement across all clusters. Requires ACM Hub. |
| Manual `oc apply` per cluster | Current state (Step 0). Simple but does not scale and creates operational burden. |
| ArgoCD ApplicationSets with cluster generators | Can deploy to multiple clusters from a single Argo CD instance, but lacks ACM's policy engine and cluster lifecycle management. |
| Hive + ClusterDeployments | Useful for cluster provisioning, not specifically for application placement. |
