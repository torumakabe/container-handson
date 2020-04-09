provider "azurerm" {
  version = "~>2.5"
  features {}
}

resource "azurerm_virtual_network" "vnet_default" {
  name                = "vnet-default"
  resource_group_name = var.aks_cluster_rg
  location            = var.aks_cluster_location
  address_space       = ["10.0.0.0/8"]
}

resource "azurerm_subnet" "aks" {
  name                 = "subnet-aks"
  resource_group_name  = var.aks_cluster_rg
  virtual_network_name = azurerm_virtual_network.vnet_default.name
  address_prefix       = "10.240.0.0/16"
}
