output "vnet_default_name" {
  value = azurerm_virtual_network.vnet_default.name
}
output "subnet_aks_id" {
  value = azurerm_subnet.aks.id
}
