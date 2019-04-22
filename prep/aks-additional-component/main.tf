provider "azurerm" {
  version = "~>1.25"
}

/*
ToDo: Replace kubeconfig auth. with Terraform data source & add helm provider
When this helm issue has been resolved https://github.com/terraform-providers/terraform-provider-helm/issues/148
*/
provider "kubernetes" {
  version = "~>1.6"

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

resource "kubernetes_cluster_role" "log_reader" {
  metadata {
    name = "containerhealth-log-reader"
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get"]
  }
}

resource "kubernetes_cluster_role_binding" "log_reader" {
  metadata {
    name = "containerhealth-read-logs-global"
  }

  role_ref {
    kind      = "ClusterRole"
    name      = "containerhealth-log-reader"
    api_group = "rbac.authorization.k8s.io"
  }

  subject {
    kind      = "User"
    name      = "clusterUser"
    api_group = "rbac.authorization.k8s.io"
  }
}

/*
ToDo: Replace it with tillerless Helm v3 
*/
resource "kubernetes_service_account" "tiller" {
  metadata {
    name      = "tiller"
    namespace = "kube-system"
  }

  automount_service_account_token = true
}

/*
ToDo: Replace it with tillerless Helm v3 
*/
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

/*
ToDo: Replace it with tillerless Helm v3 
*/
resource "kubernetes_deployment" "tiller" {
  metadata {
    name      = "tiller-deploy"
    namespace = "${kubernetes_service_account.tiller.metadata.0.namespace}"

    labels {
      name = "tiller"
      app  = "helm"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels {
        name = "tiller"
        app  = "helm"
      }
    }

    template {
      metadata {
        labels {
          name = "tiller"
          app  = "helm"
        }
      }

      spec {
        container {
          image             = "${var.tiller_image}"
          name              = "tiller"
          image_pull_policy = "IfNotPresent"
          command           = ["/tiller"]
          args              = ["--listen=localhost:44134"]

          env {
            name  = "TILLER_NAMESPACE"
            value = "${kubernetes_service_account.tiller.metadata.0.namespace}"
          }

          env {
            name  = "TILLER_HISTORY_MAX"
            value = "0"
          }

          liveness_probe {
            http_get {
              path = "/liveness"
              port = "44135"
            }

            initial_delay_seconds = "1"
            timeout_seconds       = "1"
          }

          readiness_probe {
            http_get {
              path = "/readiness"
              port = "44135"
            }

            initial_delay_seconds = "1"
            timeout_seconds       = "1"
          }

          volume_mount {
            mount_path = "/var/run/secrets/kubernetes.io/serviceaccount"
            name       = "${kubernetes_service_account.tiller.default_secret_name}"
            read_only  = true
          }
        }

        volume {
          name = "${kubernetes_service_account.tiller.default_secret_name}"

          secret {
            secret_name = "${kubernetes_service_account.tiller.default_secret_name}"
          }
        }

        service_account_name = "${kubernetes_service_account.tiller.metadata.0.name}"
      }
    }
  }
}

resource "kubernetes_namespace" "istio-system" {
  metadata {
    name = "istio-system"
  }
}

resource "kubernetes_secret" "kiali" {
  metadata {
    name      = "kiali"
    namespace = "${kubernetes_namespace.istio-system.metadata.0.name}"

    labels {
      app = "kiali"
    }
  }

  data {
    username   = "${var.kiali_username}"
    passphrase = "${var.kiali_pass}"
  }

  type = "Opaque"
}

resource "kubernetes_secret" "grafana" {
  metadata {
    name      = "grafana"
    namespace = "${kubernetes_namespace.istio-system.metadata.0.name}"

    labels {
      app = "grafana"
    }
  }

  data {
    username   = "${var.grafana_username}"
    passphrase = "${var.grafana_pass}"
  }

  type = "Opaque"
}

/*
ToDo: Replace null resource to helm provider & resource
When this issue has been resolved https://github.com/terraform-providers/terraform-provider-helm/issues/148
*/
resource "null_resource" "istio" {
  depends_on = ["kubernetes_namespace.istio-system", "kubernetes_service_account.tiller", "kubernetes_cluster_role_binding.tiller", "kubernetes_deployment.tiller", "kubernetes_secret.kiali", "kubernetes_secret.grafana"]

  provisioner "local-exec" {
    command = <<EOT
      mkdir -p .download
      curl -sL "https://github.com/istio/istio/releases/download/$${ISTIO_VERSION}/istio-$${ISTIO_VERSION}-linux.tar.gz" | tar xz -C ./.download/
    EOT

    environment {
      ISTIO_VERSION = "${var.istio_version}"
    }
  }

  provisioner "local-exec" {
    command = <<EOT
      helm init --client-only
      for i in {1..60}; do helm ls > /dev/null 2>&1 && exit 0 || sleep 1; done; exit 1
    EOT
  }

  provisioner "local-exec" {
    command = <<EOT
      helm upgrade --install istio-init ./.download/istio-$${ISTIO_VERSION}/install/kubernetes/helm/istio-init  --namespace istio-system --force --wait
      helm upgrade --install istio ./.download/istio-$${ISTIO_VERSION}/install/kubernetes/helm/istio  --namespace istio-system \
        --set global.controlPlaneSecurityEnabled=true \
        --set grafana.enabled=true \
        --set tracing.enabled=true \
        --set kiali.enabled=true \
        --force --wait
    EOT

    environment {
      ISTIO_VERSION = "${var.istio_version}"
    }
  }
}

/* Run the followings manually for cleanup Istio environment before destroy (Workaround)
helm delete --purge istio
helm delete --purge istio-init
helm reset --force
ISTIO_VERSION=1.1.2
kubectl delete -f ./.download/istio-${ISTIO_VERSION}/install/kubernetes/helm/istio-init/files
*/

