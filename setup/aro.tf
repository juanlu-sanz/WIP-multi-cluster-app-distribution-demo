# -----------------------------------------------------------------------------
# ARO Cluster: Hub (ACM control plane)
# Pod/Service CIDRs are unique per cluster to support Submariner without globalnet.
# -----------------------------------------------------------------------------

resource "azurerm_redhat_openshift_cluster" "hub" {
  name                = "${var.demo_name}-hub"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name

  cluster_profile {
    domain      = "${var.demo_name}-hub-${local.name_suffix}"
    version     = var.aro_version
    pull_secret = local.pull_secret
  }

  network_profile {
    pod_cidr     = "10.128.0.0/14"
    service_cidr = "172.30.0.0/16"
  }

  main_profile {
    vm_size   = "Standard_D8s_v3"
    subnet_id = azurerm_subnet.hub_master.id
  }

  worker_profile {
    vm_size      = var.aro_worker_vm_size
    disk_size_gb = 128
    node_count   = var.aro_worker_count
    subnet_id    = azurerm_subnet.hub_worker.id
  }

  api_server_profile {
    visibility = "Public"
  }

  ingress_profile {
    visibility = "Public"
  }

  service_principal {
    client_id     = var.azure_client_id
    client_secret = var.azure_client_secret
  }

  depends_on = [
    azurerm_role_assignment.aro_rp_vnet,
    azurerm_role_assignment.aro_sp_vnet,
  ]
}

# -----------------------------------------------------------------------------
# ARO Cluster: Cluster B (managed cluster on Azure)
# Uses different pod/service CIDRs to avoid overlap with Hub and Cluster A.
# -----------------------------------------------------------------------------

resource "azurerm_redhat_openshift_cluster" "cluster_b" {
  name                = "${var.demo_name}-cluster-b"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name

  cluster_profile {
    domain      = "${var.demo_name}-cb-${local.name_suffix}"
    version     = var.aro_version
    pull_secret = local.pull_secret
  }

  network_profile {
    pod_cidr     = "10.132.0.0/14"
    service_cidr = "172.31.0.0/16"
  }

  main_profile {
    vm_size   = "Standard_D8s_v3"
    subnet_id = azurerm_subnet.cluster_b_master.id
  }

  worker_profile {
    vm_size      = var.aro_worker_vm_size
    disk_size_gb = 128
    node_count   = var.aro_worker_count
    subnet_id    = azurerm_subnet.cluster_b_worker.id
  }

  api_server_profile {
    visibility = "Public"
  }

  ingress_profile {
    visibility = "Public"
  }

  service_principal {
    client_id     = var.azure_client_id
    client_secret = var.azure_client_secret
  }

  depends_on = [
    azurerm_role_assignment.aro_rp_vnet,
    azurerm_role_assignment.aro_sp_vnet,
  ]
}
