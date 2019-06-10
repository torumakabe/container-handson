module "network" {
  source = "../modules/network"

  aks_cluster_rg       = var.aks_cluster_rg
  aks_cluster_location = var.aks_cluster_location
}

module "aks" {
  source = "../modules/aks"

  aks_cluster_name          = var.aks_cluster_name
  aks_cluster_rg            = var.aks_cluster_rg
  aks_cluster_location      = var.aks_cluster_location
  aks_subnet_id             = module.network.aks_subnet_id
  la_workspace_name_for_aks = var.la_workspace_name_for_aks
  la_workspace_rg_for_aks   = var.la_workspace_rg_for_aks

}
