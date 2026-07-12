# -----------------------------------------------------------------------------
# AWS account identity
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# OIDC Configuration (managed by Red Hat)
# -----------------------------------------------------------------------------

resource "rhcs_rosa_oidc_config" "cluster_b" {
  managed = true
}

# -----------------------------------------------------------------------------
# IAM Account Roles
# Created via the rosa CLI because the trust policies and permission boundaries
# are version-specific and the CLI always generates the correct set.
# -----------------------------------------------------------------------------

resource "terraform_data" "rosa_account_roles" {
  input = var.demo_name

  provisioner "local-exec" {
    command = <<-EOT
      rosa login --token="${var.rhcs_token}"
      rosa create account-roles --hosted-cp \
        --mode auto \
        --prefix "${var.demo_name}" \
        --yes
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      rosa delete account-roles --hosted-cp \
        --prefix "${self.input}" \
        --mode auto --yes 2>/dev/null || true
    EOT
  }
}

# -----------------------------------------------------------------------------
# IAM Operator Roles
# These trust the OIDC provider and are required before the cluster can
# finish bootstrapping.
# -----------------------------------------------------------------------------

resource "terraform_data" "rosa_operator_roles" {
  depends_on = [
    rhcs_rosa_oidc_config.cluster_b,
    terraform_data.rosa_account_roles,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      rosa login --token="${var.rhcs_token}"
      rosa create operator-roles --hosted-cp \
        --prefix "${var.demo_name}" \
        --oidc-config-id "${rhcs_rosa_oidc_config.cluster_b.id}" \
        --installer-role-arn "${local.rosa_installer_role_arn}" \
        --mode auto --yes
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      rosa delete operator-roles \
        --prefix "${var.demo_name}" \
        --mode auto --yes 2>/dev/null || true
    EOT
  }
}

# Construct role ARNs from the naming convention instead of data sources,
# so terraform plan works before the roles exist.
locals {
  rosa_account_id         = data.aws_caller_identity.current.account_id
  rosa_installer_role_arn = "arn:aws:iam::${local.rosa_account_id}:role/${var.demo_name}-HCP-ROSA-Installer-Role"
  rosa_support_role_arn   = "arn:aws:iam::${local.rosa_account_id}:role/${var.demo_name}-HCP-ROSA-Support-Role"
  rosa_worker_role_arn    = "arn:aws:iam::${local.rosa_account_id}:role/${var.demo_name}-HCP-ROSA-Worker-Role"
}

# -----------------------------------------------------------------------------
# ROSA HCP Cluster
# Pod/Service CIDRs are unique to avoid overlap with the ARO clusters
# (required for Submariner without globalnet).
# -----------------------------------------------------------------------------

resource "rhcs_cluster_rosa_hcp" "cluster_b" {
  name                   = "${var.demo_name}-cluster-b"
  cloud_region           = var.aws_region
  aws_account_id         = local.rosa_account_id
  aws_billing_account_id = local.rosa_account_id
  version                = "openshift-v${var.rosa_version}"

  sts {
    role_arn         = local.rosa_installer_role_arn
    support_role_arn = local.rosa_support_role_arn
    instance_iam_roles {
      worker_role_arn = local.rosa_worker_role_arn
    }
    operator_role_prefix = var.demo_name
    oidc_config_id       = rhcs_rosa_oidc_config.cluster_b.id
  }

  aws_subnet_ids     = [for s in aws_subnet.private : s.id]
  availability_zones = [for s in aws_subnet.private : s.availability_zone]

  replicas             = var.rosa_worker_count
  compute_machine_type = var.rosa_worker_instance_type

  machine_cidr = aws_vpc.rosa.cidr_block
  pod_cidr     = "10.136.0.0/14"
  service_cidr = "172.32.0.0/16"

  properties = {
    rosa_creator_arn = data.aws_caller_identity.current.arn
  }

  wait_for_create_complete    = true
  wait_for_std_compute_nodes_complete = true

  depends_on = [
    terraform_data.rosa_account_roles,
    terraform_data.rosa_operator_roles,
    aws_nat_gateway.rosa,
  ]
}
