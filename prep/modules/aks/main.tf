provider "azurerm" {
  version = "~>1.29"
}

data "azurerm_log_analytics_workspace" "aks" {
  name                = var.la_workspace_name_for_aks
  resource_group_name = var.la_workspace_rg_for_aks
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  kubernetes_version  = "1.13.5"
  location            = var.aks_cluster_location
  resource_group_name = var.aks_cluster_rg
  dns_prefix          = var.aks_cluster_name

  agent_pool_profile {
    name            = "pool1"
    type            = "VirtualMachineScaleSets"
    vnet_subnet_id  = var.aks_subnet_id
    count           = 3
    vm_size         = "Standard_D2s_v3"
    os_type         = "Linux"
    os_disk_size_gb = 30
  }

  service_principal {
    client_id     = var.service_principal
    client_secret = var.service_principal_client_secret
  }

  role_based_access_control {
    enabled = true
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  addon_profile {
    oms_agent {
      enabled                    = true
      log_analytics_workspace_id = data.azurerm_log_analytics_workspace.aks.id
    }
  }
}
