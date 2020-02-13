output "aks_service_principal_object_id" {
  value = azuread_service_principal.aks.id
}

output "grafana_password" {
  value = random_string.grafana_password.result
}
