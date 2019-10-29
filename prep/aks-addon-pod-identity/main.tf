provider "azurerm" {
  version = "~>1.36"
}

provider "azuread" {
  version = "~>0.6"
}

provider "helm" {
  version = "~>0.10"

  install_tiller  = false
  namespace       = "kube-system"
  service_account = "tiller"
}

data "azurerm_client_config" "current" {}

data "azuread_user" "current" {
  user_principal_name = var.user_principal_name
}

data "helm_repository" "aad_pod_identity" {
  name     = var.aad_pod_identity_helm_repository_name
  url      = var.aad_pod_identity_helm_repository_url
  username = var.aad_pod_identity_helm_repository_username
  password = var.aad_pod_identity_helm_repository_password
}

resource "azurerm_user_assigned_identity" "aad_pod_identity" {
  resource_group_name = var.aks_cluster_rg
  location            = var.aks_cluster_location

  name = "aad-pod-identity"
}

resource "azurerm_key_vault" "aks" {
  name                = "${var.aks_cluster_name}"
  location            = var.aks_cluster_location
  resource_group_name = var.aks_cluster_rg
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku {
    name = "standard"
  }

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azuread_user.current.id

    secret_permissions = [
      "set",
      "get",
      "list",
      "delete"
    ]
  }

  access_policy {

    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_user_assigned_identity.aad_pod_identity.principal_id

    secret_permissions = [

      "get",
      "list"
    ]
  }
}

resource "azurerm_key_vault_secret" "joke" {
  name         = "joke"
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
  principal_id         = var.aks_cluster_sp_object_id
}

resource "helm_release" "aad_pod_identity" {
  name       = "aad-pod-identity"
  repository = data.helm_repository.aad_pod_identity.metadata[0].name
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
    value = "joke"
  }
}

