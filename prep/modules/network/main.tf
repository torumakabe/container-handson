provider "azurerm" {
  version = "~>1.30"
}

resource "azurerm_virtual_network" "default_vnet" {
  name                = "default_vnet"
  resource_group_name = var.aks_cluster_rg
  location            = var.aks_cluster_location
  address_space       = ["10.0.0.0/8"]
}

resource "azurerm_subnet" "aks" {
  name                 = "aks_subnet"
  resource_group_name  = var.aks_cluster_rg
  virtual_network_name = azurerm_virtual_network.default_vnet.name
  address_prefix       = "10.240.0.0/16"
}
