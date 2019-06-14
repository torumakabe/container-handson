provider "azurerm" {
  version = "~>1.30"
}

provider "helm" {
  version = "~>0.9"

  install_tiller  = false
  namespace       = "kube-system"
  service_account = "tiller"
}

data "helm_repository" "spv" {
  name = "spv"
  url  = "https://charts.spvapi.no"
}

resource "azurerm_user_assigned_identity" "aad_pod_identity" {
  resource_group_name = var.aks_cluster_rg
  location            = var.aks_cluster_location

  name = "aad-pod-identity"
}

resource "azurerm_key_vault" "aks" {
  name                = "aksvault"
  location            = var.aks_cluster_location
  resource_group_name = var.aks_cluster_rg
  tenant_id           = var.aad_tenant_id

  sku {
    name = "standard"
  }

  access_policy {
    tenant_id = var.aad_tenant_id
    object_id = azurerm_user_assigned_identity.aad_pod_identity.client_id

    secret_permissions = [
      "get", "list",
    ]
  }
}

resource "azurerm_key_vault_secret" "sample" {
  name         = "sample"
  value        = var.secret_value
  key_vault_id = azurerm_key_vault.aks.id
}

resource "azurerm_role_assignment" "pod_identitiy_to_vault" {
  scope                = azurerm_key_vault.aks.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.aad_pod_identity.principal_id
}

resource "azurerm_role_assignment" "aks_to_pod_identity" {
  scope                = azurerm_user_assigned_identity.aad_pod_identity.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = var.aks_cluster_sp_id
}

resource "helm_release" "aad_pod_identity" {
  depends_on = [
  ]
  name       = "aad-pod-identity"
  repository = data.helm_repository.spv.metadata[0].name
  chart      = "aad-pod-identity"

  set {
    name  = "azureIdentity.resourceID"
    value = azurerm_user_assigned_identity.aad_pod_identity.id
  }

  set {
    name  = "azureIdentity.clientID"
    value = azurerm_user_assigned_identity.aad_pod_identity.client_id
  }

  set {
    name  = "azureIdentityBinding.selector"
    value = "demo"
  }
}

