output "keyvault_name" {
  value = azurerm_key_vault.aks.name
}

output "keyvault_secret_name" {
  value = azurerm_key_vault_secret.sample.name
}

output "keyvault_secret_version" {
  value = azurerm_key_vault_secret.sample.version
}
