output "default_vnet_name" {
  value = azurerm_virtual_network.default_vnet.name
}
output "aks_subnet_id" {
  value = azurerm_subnet.aks.id
}
