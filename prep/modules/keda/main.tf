/*
ToDo: Replace kubeconfig auth. with Terraform data source & add helm provider
When this helm issue has been resolved https://github.com/terraform-providers/terraform-provider-helm/issues/148
*/
provider "kubernetes" {
  version = "~>1.8"
  /*
  load_config_file       = false
  host                   = "${data.azurerm_kubernetes_cluster.aks.kube_config.0.host}"
  client_certificate     = "${base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)}"
  client_key             = "${base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_key)}"
  cluster_ca_certificate = "${base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)}"
*/
}

provider "helm" {
  install_tiller  = false
  namespace       = "kube-system"
  service_account = "tiller"
}

resource "kubernetes_namespace" "keda" {
  metadata {
    name = "keda"
  }
}

data "helm_repository" "kedacore" {
  name = "kedacore"
  url  = "https://kedacore.azureedge.net/helm"
}

resource "helm_release" "keda" {
  depends_on = [
    kubernetes_namespace.keda
  ]
  name       = "keda-edge"
  repository = data.helm_repository.kedacore.metadata[0].name
  chart      = "keda-edge"
  devel      = true
  namespace  = "keda"

  set {
    name  = "logLevel"
    value = "debug"
  }
}

