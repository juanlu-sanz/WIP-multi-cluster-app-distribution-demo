# -----------------------------------------------------------------------------
# Cluster API URLs
# -----------------------------------------------------------------------------

output "hub_api_url" {
  value       = azurerm_redhat_openshift_cluster.hub.api_server_profile[0].url
  description = "API server URL for the ACM Hub cluster (Azure)."
}

output "cluster_a_api_url" {
  value       = rhcs_cluster_rosa_hcp.cluster_a.api_url
  description = "API server URL for Cluster A (AWS)."
}

output "cluster_b_api_url" {
  value       = azurerm_redhat_openshift_cluster.cluster_b.api_server_profile[0].url
  description = "API server URL for Cluster B (Azure)."
}

# -----------------------------------------------------------------------------
# Console URLs
# -----------------------------------------------------------------------------

output "hub_console_url" {
  value       = azurerm_redhat_openshift_cluster.hub.console_url
  description = "Web console URL for the Hub cluster."
}

output "cluster_a_console_url" {
  value       = rhcs_cluster_rosa_hcp.cluster_a.console_url
  description = "Web console URL for Cluster A."
}

output "cluster_b_console_url" {
  value       = azurerm_redhat_openshift_cluster.cluster_b.console_url
  description = "Web console URL for Cluster B."
}

# -----------------------------------------------------------------------------
# Resource identifiers (used by post-install.sh)
# -----------------------------------------------------------------------------

output "azure_resource_group" {
  value       = azurerm_resource_group.demo.name
  description = "Azure resource group containing the ARO clusters."
}

output "hub_cluster_name" {
  value       = azurerm_redhat_openshift_cluster.hub.name
  description = "ARO cluster name for the Hub."
}

output "rosa_cluster_name" {
  value       = rhcs_cluster_rosa_hcp.cluster_a.name
  description = "ROSA HCP cluster name for Cluster A."
}

output "rosa_cluster_id" {
  value       = rhcs_cluster_rosa_hcp.cluster_a.id
  description = "ROSA HCP cluster ID for Cluster A."
}

output "cluster_b_cluster_name" {
  value       = azurerm_redhat_openshift_cluster.cluster_b.name
  description = "ARO cluster name for Cluster B."
}

output "demo_name" {
  value       = var.demo_name
  description = "Demo name prefix used for all resources."
}

# -----------------------------------------------------------------------------
# Workshop variables (ready-to-paste export block)
# Run: terraform output -raw workshop_exports
# -----------------------------------------------------------------------------

output "workshop_exports" {
  value = <<-EOT
    export HUB_API_URL="${azurerm_redhat_openshift_cluster.hub.api_server_profile[0].url}"
    export CLUSTER_A_API_URL="${rhcs_cluster_rosa_hcp.cluster_a.api_url}"
    export CLUSTER_B_API_URL="${azurerm_redhat_openshift_cluster.cluster_b.api_server_profile[0].url}"
  EOT
  description = "Paste into your terminal to set the workshop variables. REMOTE_INGRESS_IP is set by post-install.sh after Submariner is configured."
}
