provider "azurerm" {
  version = "~>2.1"
  features {}
}

resource "azurerm_resource_group" "aks" {
  name     = var.aks_cluster_rg
  location = var.aks_cluster_location
}
