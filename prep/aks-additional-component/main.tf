provider "azurerm" {
  version = "~>1.24"
}

provider "kubernetes" {
  version = "~>1.5"

  /*
  load_config_file       = false
  host                   = "${data.azurerm_kubernetes_cluster.aks.kube_config.0.host}"
  client_certificate     = "${base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)}"
  client_key             = "${base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_key)}"
  cluster_ca_certificate = "${base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)}"
*/
}

data "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.aks_cluster_name}"
  resource_group_name = "${var.aks_cluster_rg}"
}

data "azurerm_log_analytics_workspace" "aks" {
  name                = "${var.la_workspace_name_for_aks}"
  resource_group_name = "${var.la_workspace_rg_for_aks}"
}

resource "kubernetes_cluster_role" "kured" {
  metadata {
    name = "kured"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["list", "delete", "get"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["daemonsets"]
    verbs      = ["get"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/eviction"]
    verbs      = ["create"]
  }
}

resource "kubernetes_cluster_role_binding" "kured" {
  metadata {
    name = "kured"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "kured"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "kured"
    namespace = "kube-system"
  }
}

resource "kubernetes_role" "kured" {
  metadata {
    name      = "kured"
    namespace = "kube-system"
  }

  rule {
    api_groups     = ["extensions"]
    resources      = ["daemonsets"]
    resource_names = ["kured"]
    verbs          = ["update"]
  }
}

resource "kubernetes_role_binding" "kured" {
  metadata {
    name      = "kured"
    namespace = "kube-system"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "kured"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "kured"
    namespace = "kube-system"
  }
}

resource "kubernetes_service_account" "kured" {
  metadata {
    name      = "kured"
    namespace = "kube-system"
  }
}

resource "kubernetes_daemonset" "kured" {
  metadata {
    name      = "kured"
    namespace = "kube-system"
  }

  spec {
    selector {
      match_labels {
        name = "kured"
      }
    }

    strategy {
      type = "RollingUpdate"
    }

    template {
      metadata {
        labels {
          name = "kured"
        }
      }

      spec {
        service_account_name = "kured"
        host_pid             = true
        restart_policy       = "Always"

        container {
          image             = "quay.io/weaveworks/kured:1.1.0"
          image_pull_policy = "IfNotPresent"
          name              = "kured"

          security_context {
            privileged = true
          }

          env {
            name = "KURED_NODE_ID"

            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          volume_mount {
            mount_path = "/var/run/secrets/kubernetes.io/serviceaccount"
            name       = "${kubernetes_service_account.kured.default_secret_name}"
            read_only  = true
          }

          command = ["/usr/bin/kured"]

          resources {
            limits {
              cpu    = "50m"
              memory = "50Mi"
            }

            requests {
              cpu    = "50m"
              memory = "50Mi"
            }
          }
        }

        volume {
          name = "${kubernetes_service_account.kured.default_secret_name}"

          secret {
            secret_name = "${kubernetes_service_account.kured.default_secret_name}"
          }
        }
      }
    }
  }
}

resource "kubernetes_service_account" "tiller" {
  metadata {
    name      = "tiller"
    namespace = "kube-system"
  }

  automount_service_account_token = true
}

resource "kubernetes_cluster_role_binding" "tiller" {
  metadata {
    name = "${kubernetes_service_account.tiller.metadata.0.name}"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "${kubernetes_service_account.tiller.metadata.0.name}"
    namespace = "kube-system"
  }
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "diag_aks"
  target_resource_id         = "${data.azurerm_kubernetes_cluster.aks.id}"
  log_analytics_workspace_id = "${data.azurerm_log_analytics_workspace.aks.id}"

  log {
    category = "kube-apiserver"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "kube-controller-manager"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "kube-scheduler"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "kube-audit"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "cluster-autoscaler"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }
}

resource "kubernetes_namespace" "istio-system" {
  metadata {
    name = "istio-system"
  }
}
