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

