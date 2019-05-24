/*
ToDo: Replace kubeconfig auth. with Terraform data source & add helm provider
When this helm issue has been resolved https://github.com/terraform-providers/terraform-provider-helm/issues/148
*/
provider "kubernetes" {
  version = "~>1.7"
  /*
  load_config_file       = false
  host                   = "${data.azurerm_kubernetes_cluster.aks.kube_config.0.host}"
  client_certificate     = "${base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)}"
  client_key             = "${base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_key)}"
  cluster_ca_certificate = "${base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)}"
*/
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
    name = kubernetes_service_account.tiller.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.tiller.metadata[0].name
    namespace = "kube-system"
  }
}

/*
ToDo: Replace it with tillerless Helm v3 
*/
resource "kubernetes_deployment" "tiller" {
  metadata {
    name      = "tiller-deploy"
    namespace = kubernetes_service_account.tiller.metadata[0].namespace

    labels = {
      name = "tiller"
      app  = "helm"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        name = "tiller"
        app  = "helm"
      }
    }

    template {
      metadata {
        labels = {
          name = "tiller"
          app  = "helm"
        }
      }

      spec {
        container {
          image             = var.tiller_image
          name              = "tiller"
          image_pull_policy = "IfNotPresent"
          command           = ["/tiller"]
          args              = ["--listen=localhost:44134"]

          env {
            name  = "TILLER_NAMESPACE"
            value = kubernetes_service_account.tiller.metadata[0].namespace
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
            name       = kubernetes_service_account.tiller.default_secret_name
            read_only  = true
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
      TILLER_NAMESPACE = kubernetes_deployment.tiller.metadata[0].namespace
    }
  }
}
