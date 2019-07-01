module "rg" {
  source = "../modules/rg"

  aks_cluster_rg       = var.aks_cluster_rg
  aks_cluster_location = var.aks_cluster_location
}

module "network" {
  source = "../modules/network"

  aks_cluster_rg       = module.rg.aks_cluster_rg_out
  aks_cluster_location = var.aks_cluster_location
}

module "aks" {
  source = "../modules/aks"

  aks_cluster_name     = var.aks_cluster_name
  aks_cluster_rg       = var.aks_cluster_rg
  aks_cluster_location = var.aks_cluster_location
  aks_subnet_id        = module.network.aks_subnet_id
  la_workspace_name    = var.la_workspace_name
  la_workspace_rg      = var.la_workspace_rg
  tiller_image         = var.tiller_image

}
