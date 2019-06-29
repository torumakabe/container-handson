provider "azurerm" {
  version = "~>1.31"
}

provider "azuread" {
  version = "~>0.4"
}

provider "random" {
  version = "~>2.0"
}

data "azurerm_subscription" "current" {}

data "azurerm_log_analytics_workspace" "aks" {
  name                = var.la_workspace_name
  resource_group_name = var.la_workspace_rg
}

resource "azuread_application" "aks" {
  name            = "${var.aks_cluster_name}-aadapp"
//  identifier_uris = ["https://${var.aks_cluster_name}-aadapp"]
}

resource "azuread_service_principal" "aks" {
  application_id = "${azuread_application.aks.application_id}"
}

resource "random_string" "password" {
  length  = 32
  special = true
}

resource "azuread_service_principal_password" "aks" {
  end_date             = "2299-12-30T23:00:00Z" # Forever
  service_principal_id = azuread_service_principal.aks.id
  value                = random_string.password.result
}

resource "azurerm_role_assignment" "aks" {
  depends_on           = ["azuread_service_principal_password.aks"]
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.aks.id

  // Waiting for AAD global replication
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

resource "azurerm_kubernetes_cluster" "aks" {
  depends_on          = ["azurerm_role_assignment.aks"]
  name                = var.aks_cluster_name
  kubernetes_version  = "1.13.5"
  location            = var.aks_cluster_location
  resource_group_name = var.aks_cluster_rg
  dns_prefix          = var.aks_cluster_name

  agent_pool_profile {
    name            = "pool1"
    type            = "VirtualMachineScaleSets"
    vnet_subnet_id  = var.aks_subnet_id
    count           = 3
    vm_size         = "Standard_D2s_v3"
    os_type         = "Linux"
    os_disk_size_gb = 30
  }

  service_principal {
    client_id     = azuread_application.aks.application_id
    client_secret = random_string.password.result
  }

  role_based_access_control {
    enabled = true
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  addon_profile {
    oms_agent {
      enabled                    = true
      log_analytics_workspace_id = data.azurerm_log_analytics_workspace.aks.id
    }
  }

  provisioner "local-exec" {
    command = <<EOT
      az aks get-credentials -g ${var.aks_cluster_rg} -n ${self.name} --admin --overwrite-existing;
    EOT
  }
}

provider "kubernetes" {
  version = "~>1.7"

  load_config_file = false
  host = "${azurerm_kubernetes_cluster.aks.kube_config.0.host}"
  client_certificate = "${base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)}"
  client_key = "${base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)}"
  cluster_ca_certificate = "${base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)}"
}

resource "kubernetes_cluster_role_binding" "kubernetes-dashboard-rule" {
  metadata {
    name = "kubernetes-dashboard-rule"
  }

  role_ref {
    kind = "ClusterRole"
    name = "cluster-admin"
    api_group = "rbac.authorization.k8s.io"
  }

  subject {
    kind = "ServiceAccount"
    namespace = "kube-system"
    name = "kubernetes-dashboard"
    api_group = ""
  }
}

/*
ToDo: Replace it with tillerless Helm v3 
*/
resource "kubernetes_service_account" "tiller" {
  metadata {
    name = "tiller"
    namespace = "kube-system"
  }
}

/*
ToDo: Replace it with tillerless Helm v3 
*/
resource "kubernetes_cluster_role_binding" "tiller" {
  metadata {
    name = kubernetes_service_account.tiller.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "ClusterRole"
    name = "cluster-admin"
  }

  subject {
    kind = "ServiceAccount"
    name = kubernetes_service_account.tiller.metadata[0].name
    namespace = "kube-system"
  }
}

/*
ToDo: Replace it with tillerless Helm v3 
*/
resource "kubernetes_deployment" "tiller" {
  metadata {
    name = "tiller-deploy"
    namespace = kubernetes_service_account.tiller.metadata[0].namespace

    labels = {
      name = "tiller"
      app = "helm"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        name = "tiller"
        app = "helm"
      }
    }

    template {
      metadata {
        labels = {
          name = "tiller"
          app = "helm"
        }
      }

      spec {
        container {
          image = var.tiller_image
          name = "tiller"
          image_pull_policy = "IfNotPresent"
          command = ["/tiller"]
          args = ["--listen=localhost:44134"]

          env {
            name = "TILLER_NAMESPACE"
            value = kubernetes_service_account.tiller.metadata[0].namespace
          }

          env {
            name = "TILLER_HISTORY_MAX"
            value = "0"
          }

          liveness_probe {
            http_get {
              path = "/liveness"
              port = "44135"
            }

            initial_delay_seconds = "1"
            timeout_seconds = "1"
          }

          readiness_probe {
            http_get {
              path = "/readiness"
              port = "44135"
            }

            initial_delay_seconds = "1"
            timeout_seconds = "1"
          }

          volume_mount {
            mount_path = "/var/run/secrets/kubernetes.io/serviceaccount"
            name = kubernetes_service_account.tiller.default_secret_name
            read_only = true
          }
        }

        volume {
          name = kubernetes_service_account.tiller.default_secret_name

          secret {
            secret_name = kubernetes_service_account.tiller.default_secret_name
          }
        }

        service_account_name = kubernetes_service_account.tiller.metadata[0].name
      }
    }
  }
}

resource "null_resource" "tiller_wait" {
  depends_on = [
    kubernetes_service_account.tiller,
    kubernetes_cluster_role_binding.tiller,
    kubernetes_deployment.tiller,
  ]

  provisioner "local-exec" {
    command = <<EOT
      helm init --client-only
      kubectl rollout status deployment/$${TILLER_DEPLOYMENT_NAME} -n $${TILLER_NAMESPACE}
    
EOT


    environment = {
      TILLER_DEPLOYMENT_NAME = kubernetes_deployment.tiller.metadata[0].name
      TILLER_NAMESPACE       = kubernetes_deployment.tiller.metadata[0].namespace
    }
  }
}
