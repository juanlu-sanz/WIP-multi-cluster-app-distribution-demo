# -----------------------------------------------------------------------------
# Azure credentials
# -----------------------------------------------------------------------------

variable "azure_subscription_id" {
  type        = string
  description = "Azure subscription ID."
}

variable "azure_tenant_id" {
  type        = string
  description = "Azure AD tenant ID."
}

variable "azure_client_id" {
  type        = string
  description = "Service principal application (client) ID. Needs Contributor + User Access Admin on the subscription."
}

variable "azure_client_secret" {
  type        = string
  sensitive   = true
  description = "Service principal client secret."
}

variable "azure_region" {
  type        = string
  default     = "westeurope"
  description = "Azure region for the Hub and Cluster B."
}

# -----------------------------------------------------------------------------
# AWS credentials
# -----------------------------------------------------------------------------

variable "aws_access_key_id" {
  type        = string
  description = "AWS IAM user access key ID. Needs AdministratorAccess (or ROSA-specific permissions)."
}

variable "aws_secret_access_key" {
  type        = string
  sensitive   = true
  description = "AWS IAM user secret access key."
}

variable "aws_region" {
  type        = string
  default     = "eu-north-1"
  description = "AWS region for Cluster A."
}

# -----------------------------------------------------------------------------
# Red Hat credentials
# -----------------------------------------------------------------------------

variable "pull_secret_path" {
  type        = string
  default     = "~/.openshift/pull-secret.json"
  description = "Path to the pull secret JSON file from console.redhat.com/openshift/downloads."
}

variable "rhcs_token" {
  type        = string
  sensitive   = true
  description = "Red Hat OCM API token from console.redhat.com/openshift/token. Used for ROSA HCP."
}

# -----------------------------------------------------------------------------
# Cluster sizing
# -----------------------------------------------------------------------------

variable "aro_worker_count" {
  type        = number
  default     = 3
  description = "Number of worker nodes per ARO cluster."
}

variable "aro_worker_vm_size" {
  type        = string
  default     = "Standard_D4s_v3"
  description = "Azure VM size for ARO worker nodes."
}

variable "aro_version" {
  type        = string
  default     = "4.15.27"
  description = "ARO OpenShift version (full patch). Run 'az aro get-versions --location <region>' to list available versions."
}

variable "rosa_worker_count" {
  type        = number
  default     = 3
  description = "Number of worker nodes for ROSA HCP."
}

variable "rosa_worker_instance_type" {
  type        = string
  default     = "m5.xlarge"
  description = "AWS instance type for ROSA HCP worker nodes."
}

variable "rosa_version" {
  type        = string
  default     = "4.15.0"
  description = "ROSA HCP OpenShift version. Run 'rosa list versions --channel-group stable --hosted-cp' to list available versions."
}

# -----------------------------------------------------------------------------
# Naming
# -----------------------------------------------------------------------------

variable "demo_name" {
  type        = string
  default     = "multicluster-demo"
  description = "Prefix for all resource names. Keep it short (max 15 chars) to avoid name length limits."

  validation {
    condition     = length(var.demo_name) <= 15
    error_message = "demo_name must be 15 characters or fewer."
  }
}
