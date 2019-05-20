provider "azurerm" {
  version = "~>1.28"
}

data "azurerm_log_analytics_workspace" "aks" {
  name                = "${var.la_workspace_name_for_aks}"
  resource_group_name = "${var.la_workspace_rg_for_aks}"
}

resource "azurerm_virtual_network" "vnet1" {
  name                = "vnet1"
  resource_group_name = "${var.aks_cluster_rg}"
  location            = "${var.aks_cluster_location}"
  address_space       = ["10.0.0.0/8"]
}

resource "azurerm_subnet" "aks" {
  name                 = "aks_subnet"
  resource_group_name  = "${var.aks_cluster_rg}"
  virtual_network_name = "${azurerm_virtual_network.vnet1.name}"
  address_prefix       = "10.240.0.0/16"
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.aks_cluster_name}"
  kubernetes_version  = "1.13.5"
  location            = "${var.aks_cluster_location}"
  resource_group_name = "${var.aks_cluster_rg}"
  dns_prefix          = "${var.aks_cluster_name}"

  agent_pool_profile {
    name            = "pool1"
    type            = "VirtualMachineScaleSets"
    vnet_subnet_id  = "${azurerm_subnet.aks.id}"
    count           = 2
    vm_size         = "Standard_D2s_v3"
    os_type         = "Linux"
    os_disk_size_gb = 30
  }

  service_principal {
    client_id     = "${var.service_principal}"
    client_secret = "${var.service_principal_client_secret}"
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
      log_analytics_workspace_id = "${data.azurerm_log_analytics_workspace.aks.id}"
    }
  }
}
