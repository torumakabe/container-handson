output "keyvault_name" {
  value = azurerm_key_vault.aks.name
}

output "keyvault_secret_name" {
  value = azurerm_key_vault_secret.joke.name
}

output "keyvault_secret_version" {
  value = azurerm_key_vault_secret.joke.version
}
