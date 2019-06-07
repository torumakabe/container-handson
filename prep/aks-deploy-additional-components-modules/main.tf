module "kured" {
  source = "../modules/kured"

  aks_cluster_name = var.aks_cluster_name
  aks_cluster_rg   = var.aks_cluster_rg
  kured_image      = var.kured_image
}

module "monitor" {
  source = "../modules/monitor"

  aks_cluster_name          = var.aks_cluster_name
  aks_cluster_rg            = var.aks_cluster_rg
  la_workspace_name_for_aks = var.la_workspace_name_for_aks
  la_workspace_rg_for_aks   = var.la_workspace_rg_for_aks

}

module "tiller" {
  source = "../modules/tiller"

  tiller_image = var.tiller_image
}

/*
module "istio" {
  source           = "../modules/istio"
  tiller_wait_flag = module.tiller.wait_flag

  istio_version    = var.istio_version
  kiali_username   = var.kiali_username
  kiali_pass       = var.kiali_pass
  grafana_username = var.grafana_username
  grafana_pass     = var.grafana_pass

}

module "keda" {
  source           = "../modules/keda"
  tiller_wait_flag = module.tiller.wait_flag
}

*/
