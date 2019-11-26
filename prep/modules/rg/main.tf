provider "azurerm" {
  version = "~>1.37"
}

resource "azurerm_resource_group" "aks" {
  name     = var.aks_cluster_rg
  location = var.aks_cluster_location
}
