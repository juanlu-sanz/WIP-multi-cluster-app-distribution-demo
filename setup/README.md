# Cluster Setup (Internal - Red Hatters Only)

This directory contains Terraform configuration and a post-install script to provision the full demo environment from scratch: 2 ARO clusters on Azure (Hub + Cluster A) and 1 ROSA HCP cluster on AWS (Cluster B).

**This is not part of the demo/workshop.** It is internal tooling for Red Hatters to spin up the infrastructure before running the walkthrough in [`00-current-state/`](../00-current-state/).

## Architecture

| Cluster | Platform | Cloud | Purpose |
|---|---|---|---|
| Hub | ARO | Azure | ACM control plane, GitOps |
| Cluster A | ARO | Azure | Managed cluster (same cloud as Hub) |
| Cluster B | ROSA HCP | AWS | Managed cluster (different cloud) |

## Prerequisites

### Tools

| Tool | Version | Install |
|---|---|---|
| `terraform` | >= 1.6 | [terraform.io](https://developer.hashicorp.com/terraform/install) |
| `oc` | 4.15+ | [mirror.openshift.com](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/) |
| `az` | latest | [docs.microsoft.com](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) |
| `rosa` | latest | [console.redhat.com](https://console.redhat.com/openshift/downloads#tool-rosa) |
| `aws` | v2 | [aws.amazon.com](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |

### Credentials

| Credential | Where to get it |
|---|---|
| Azure service principal (client ID + secret) | `az ad sp create-for-rbac --name "aro-demo" --role Contributor --scopes /subscriptions/<SUB_ID>` - also grant User Access Admin |
| Azure subscription + tenant IDs | `az account show` |
| AWS access key + secret | IAM console - needs AdministratorAccess |
| OpenShift pull secret | [console.redhat.com/openshift/downloads](https://console.redhat.com/openshift/downloads#tool-pull-secret) - save to `~/.openshift/pull-secret.json` |
| OCM API token | [console.redhat.com/openshift/token](https://console.redhat.com/openshift/token) |

### Azure resource provider

Register the ARO resource provider (one-time per subscription):

```bash
az provider register --namespace Microsoft.RedHatOpenShift --wait
az provider show --namespace Microsoft.RedHatOpenShift --query "registrationState" -o tsv
# Expected: Registered
```

### ROSA prerequisites

Enable ROSA on your AWS account (one-time):

```bash
rosa login --token="<your-ocm-token>"
rosa verify quota --region=eu-north-1
rosa verify permissions
```

## Quick Start

```bash
cd setup/

# 1. Configure credentials
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 2. Provision infrastructure (~30-40 minutes)
terraform init
terraform apply

# 3. Install operators and import clusters (~10 minutes)
./post-install.sh

# 4. Start the demo
cd ..
# Follow 00-current-state/README.md
```

## What Terraform Creates

### Azure (2 ARO clusters)

- 1 resource group
- 1 VNet (10.0.0.0/16) with 4 subnets (master + worker per cluster)
- ARO Hub cluster (pod CIDR: 10.128.0.0/14, service CIDR: 172.30.0.0/16)
- ARO Cluster A (pod CIDR: 10.132.0.0/14, service CIDR: 172.31.0.0/16)
- Role assignments for the ARO resource provider

### AWS (1 ROSA HCP cluster)

- 1 VPC (10.1.0.0/16) with 3 private + 3 public subnets
- Internet gateway, NAT gateway, route tables
- ROSA HCP account IAM roles (via `rosa` CLI)
- ROSA HCP operator IAM roles (via `rosa` CLI)
- OIDC configuration
- ROSA HCP Cluster B (pod CIDR: 10.136.0.0/14, service CIDR: 172.32.0.0/16)

### CIDR allocation

Pod and service CIDRs are intentionally non-overlapping across all three clusters. This is required for Submariner (Step 02 of the demo) to work without globalnet.

| Cluster | VNet/VPC CIDR | Pod CIDR | Service CIDR |
|---|---|---|---|
| Hub | 10.0.0.0/16 | 10.128.0.0/14 | 172.30.0.0/16 |
| Cluster A | 10.0.0.0/16 | 10.132.0.0/14 | 172.31.0.0/16 |
| Cluster B | 10.1.0.0/16 | 10.136.0.0/14 | 172.32.0.0/16 |

## What post-install.sh Does

1. Retrieves cluster credentials (ARO via `az`, ROSA via `rosa create admin`)
2. Logs in to all three clusters and renames contexts to `hub`, `cluster-a`, `cluster-b`
3. Installs ACM 2.11 operator on Hub and creates MultiClusterHub
4. Installs OpenShift GitOps on Hub
5. Imports Cluster A and Cluster B into ACM as managed clusters
6. Installs OpenShift Service Mesh 3.0 operator on Cluster A and Cluster B
7. Prints the workshop variables ready to paste

## Teardown

Destroy everything when the demo is done to avoid ongoing charges:

```bash
cd setup/

# Remove operators and ACM objects first (cleaner than force-destroying)
# This is optional - terraform destroy handles it, but avoids finalizer hangs.
oc delete multiclusterhub multiclusterhub -n open-cluster-management --context hub --ignore-not-found
oc delete managedcluster cluster-a cluster-b --context hub --ignore-not-found

# Destroy all infrastructure
terraform destroy
```

## Cost Estimate

| Resource | Approximate cost |
|---|---|
| ARO Hub (3 workers x Standard_D4s_v3) | ~$1.50/hour |
| ARO Cluster A (3 workers x Standard_D4s_v3) | ~$1.50/hour |
| ROSA HCP Cluster B (3 workers x m5.xlarge) | ~$1.50/hour |
| NAT Gateway (AWS) | ~$0.05/hour |
| **Total** | **~$4.50-5.00/hour** |

**Destroy the environment after every demo session.**

## Troubleshooting

### ARO creation fails with "ResourceProviderNotRegistered"

Register the provider: `az provider register --namespace Microsoft.RedHatOpenShift --wait`

### ARO creation fails with "SubnetNotFound" or role assignment errors

Ensure the service principal has User Access Admin on the subscription (not just Contributor).

### ROSA account roles fail to create

Check that `rosa verify permissions` passes and your AWS user has AdministratorAccess.

### Post-install hangs waiting for MultiClusterHub

ACM can take up to 15 minutes. Check progress: `oc get multiclusterhub -n open-cluster-management --context hub -o yaml`

### Cluster import fails

Verify the managed cluster is reachable from the Hub: `oc get managedcluster --context hub`

### Version not available

- ARO: `az aro get-versions --location westeurope -o table`
- ROSA: `rosa list versions --channel-group stable --hosted-cp`

Update `aro_version` or `rosa_version` in `terraform.tfvars` accordingly.
