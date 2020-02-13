/*
ToDo: Replace kubeconfig auth. with Terraform data source & add helm provider
When this helm issue has been resolved https://github.com/terraform-providers/terraform-provider-helm/issues/148
*/
provider "kubernetes" {
  version = "~>1.10.0"
  /*
  load_config_file       = false
  host                   = "${data.azurerm_kubernetes_cluster.aks.kube_config.0.host}"
  client_certificate     = "${base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)}"
  client_key             = "${base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_key)}"
  cluster_ca_certificate = "${base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)}"
*/
}

resource "kubernetes_namespace" "istio-system" {
  metadata {
    name = "istio-system"
  }
}

resource "kubernetes_secret" "kiali" {
  metadata {
    name      = "kiali"
    namespace = kubernetes_namespace.istio-system.metadata[0].name

    labels = {
      app = "kiali"
    }
  }

  data = {
    username   = var.kiali_username
    passphrase = var.kiali_pass
  }

  type = "Opaque"
}

resource "kubernetes_secret" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.istio-system.metadata[0].name

    labels = {
      app = "grafana"
    }
  }

  data = {
    username   = var.grafana_username
    passphrase = var.grafana_pass
  }

  type = "Opaque"
}

/*
ToDo: Replace null resource to helm provider & resource
When this issue has been resolved https://github.com/terraform-providers/terraform-provider-helm/issues/148
*/
resource "null_resource" "istio" {
  depends_on = [
    var.tiller_wait_flag,
    kubernetes_namespace.istio-system,
    kubernetes_secret.kiali,
    kubernetes_secret.grafana,
  ]

  provisioner "local-exec" {
    command = <<EOT
      mkdir -p .download
      curl -sL "https://github.com/istio/istio/releases/download/$${ISTIO_VERSION}/istio-$${ISTIO_VERSION}-linux.tar.gz" | tar xz -C ./.download/
    
EOT


    environment = {
      ISTIO_VERSION = var.istio_version
    }
  }

  # Workaround: Verify number of CRDs (53) before Istio installation to avoid validation error https://github.com/istio/istio/issues/11551
  provisioner "local-exec" {
    command = <<EOT
      helm upgrade --install istio-init ./.download/istio-$${ISTIO_VERSION}/install/kubernetes/helm/istio-init  --namespace istio-system --force
      $${MODULE_PATH}/verify_crd.sh
    
    EOT


    environment = {
      ISTIO_VERSION = var.istio_version
      MODULE_PATH   = path.module
    }
  }

  provisioner "local-exec" {
    command = <<EOT
        helm upgrade --install istio ./.download/istio-$${ISTIO_VERSION}/install/kubernetes/helm/istio  --namespace istio-system \
          --set global.controlPlaneSecurityEnabled=true \
          --set grafana.enabled=true \
          --set tracing.enabled=true \
          --set kiali.enabled=true \
          --force
      
  EOT


    environment = {
      ISTIO_VERSION = var.istio_version
    }
  }
}
