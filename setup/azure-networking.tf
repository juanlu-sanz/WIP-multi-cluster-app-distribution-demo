# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "demo" {
  name     = "${var.demo_name}-rg"
  location = var.azure_region

  tags = {
    purpose = "multicluster-demo"
  }
}

# -----------------------------------------------------------------------------
# Virtual Network (shared by both ARO clusters)
# -----------------------------------------------------------------------------

resource "azurerm_virtual_network" "demo" {
  name                = "${var.demo_name}-vnet"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  address_space       = ["10.0.0.0/16"]
}

# -----------------------------------------------------------------------------
# Hub cluster subnets
# ARO requires separate master and worker subnets, each at least /23.
# -----------------------------------------------------------------------------

resource "azurerm_subnet" "hub_master" {
  name                                          = "${var.demo_name}-hub-master"
  resource_group_name                           = azurerm_resource_group.demo.name
  virtual_network_name                          = azurerm_virtual_network.demo.name
  address_prefixes                              = ["10.0.0.0/23"]
  private_link_service_network_policies_enabled = false
}

resource "azurerm_subnet" "hub_worker" {
  name                 = "${var.demo_name}-hub-worker"
  resource_group_name  = azurerm_resource_group.demo.name
  virtual_network_name = azurerm_virtual_network.demo.name
  address_prefixes     = ["10.0.2.0/23"]
}

# -----------------------------------------------------------------------------
# Cluster A subnets
# -----------------------------------------------------------------------------

resource "azurerm_subnet" "cluster_a_master" {
  name                                          = "${var.demo_name}-cluster-a-master"
  resource_group_name                           = azurerm_resource_group.demo.name
  virtual_network_name                          = azurerm_virtual_network.demo.name
  address_prefixes                              = ["10.0.4.0/23"]
  private_link_service_network_policies_enabled = false
}

resource "azurerm_subnet" "cluster_a_worker" {
  name                 = "${var.demo_name}-cluster-a-worker"
  resource_group_name  = azurerm_resource_group.demo.name
  virtual_network_name = azurerm_virtual_network.demo.name
  address_prefixes     = ["10.0.6.0/23"]
}

# -----------------------------------------------------------------------------
# ARO Resource Provider - VNet access
# The Azure Red Hat OpenShift RP needs Network Contributor on the VNet.
# -----------------------------------------------------------------------------

data "azuread_service_principal" "aro_rp" {
  client_id = "f1dd0a37-89c6-4e07-bcd1-ffd3d43d8875"
}

resource "azurerm_role_assignment" "aro_rp_vnet" {
  scope                = azurerm_virtual_network.demo.id
  role_definition_name = "Network Contributor"
  principal_id         = data.azuread_service_principal.aro_rp.object_id
}

# The cluster service principal also needs Contributor on the VNet.
data "azuread_service_principal" "aro_sp" {
  client_id = var.azure_client_id
}

resource "azurerm_role_assignment" "aro_sp_vnet" {
  scope                = azurerm_virtual_network.demo.id
  role_definition_name = "Contributor"
  principal_id         = data.azuread_service_principal.aro_sp.object_id
}
