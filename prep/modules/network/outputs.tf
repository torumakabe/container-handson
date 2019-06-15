output "vnet_default_name" {
  value = azurerm_virtual_network.vnet_default.name
}
output "aks_subnet_id" {
  value = azurerm_subnet.aks.id
}
