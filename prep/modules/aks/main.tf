provider "azurerm" {
  version = "~>2.4"
  features {}
}

provider "azuread" {
  version = "~>0.8"
}

provider "random" {
  version = "~>2.1"
}

data "azurerm_subscription" "current" {}

data "azurerm_log_analytics_workspace" "aks" {
  name                = var.la_workspace_name
  resource_group_name = var.la_workspace_rg
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  kubernetes_version  = "1.16.7"
  location            = var.aks_cluster_location
  resource_group_name = var.aks_cluster_rg
  dns_prefix          = var.aks_cluster_name

  default_node_pool {
    name                = "pool1"
    type                = "VirtualMachineScaleSets"
    enable_auto_scaling = true
    vnet_subnet_id      = var.aks_subnet_id
    availability_zones  = [1, 2, 3]
    node_count          = 3
    min_count           = 3
    max_count           = 3
    vm_size             = "Standard_D2s_v3"
  }

  service_principal {
    client_id     = "msi"
    client_secret = "dummy"
  }

  identity {
    type = "SystemAssigned"
  }

  role_based_access_control {
    enabled = true
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    load_balancer_profile {
      managed_outbound_ip_count = 1
    }
  }

  addon_profile {
    oms_agent {
      enabled                    = true
      log_analytics_workspace_id = data.azurerm_log_analytics_workspace.aks.id
    }
  }

  // Workaround https://github.com/terraform-providers/terraform-provider-azurerm/issues/6215
  lifecycle {
    ignore_changes = [windows_profile]
  }

  provisioner "local-exec" {
    command = <<EOT
      az aks get-credentials -g ${var.aks_cluster_rg} -n ${self.name} --admin --overwrite-existing;
    EOT
  }
}

provider "kubernetes" {
  version = "~>1.11"

  load_config_file       = false
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "aks-diag"
  target_resource_id         = azurerm_kubernetes_cluster.aks.id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.aks.id

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

  metric {
    category = "AllMetrics"
    enabled  = false

    retention_policy {
      days    = 0
      enabled = false
    }
  }
}

resource "kubernetes_cluster_role_binding" "kubernetes-dashboard-rule" {
  metadata {
    name = "kubernetes-dashboard-rule"
  }

  role_ref {
    kind      = "ClusterRole"
    name      = "cluster-admin"
    api_group = "rbac.authorization.k8s.io"
  }

  subject {
    kind      = "ServiceAccount"
    namespace = "kube-system"
    name      = "kubernetes-dashboard"
    api_group = ""
  }
}

resource "kubernetes_cluster_role" "log_reader" {
  metadata {
    name = "containerhealth-log-reader"
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log", "events"]
    verbs      = ["get", "list"]
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

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

provider "helm" {
  version = "~>1.1"

  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

data "helm_repository" "stable" {
  name = "stable"
  url  = "https://kubernetes-charts.storage.googleapis.com/"
}

resource "random_string" "grafana_password" {
  length  = 32
  special = true
}

resource "kubernetes_storage_class" "managed-premium-bind-wait" {
  metadata {
    name = "managed-premium-bind-wait"
  }
  storage_provisioner = "kubernetes.io/azure-disk"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters = {
    storageaccounttype = "Premium_LRS"
    kind               = "Managed"
  }
}

resource "kubernetes_daemonset" "image_puller" {
  metadata {
    name      = "image-puller"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  spec {
    selector {
      match_labels = {
        name = "image-puller"
      }
    }

    template {
      metadata {
        labels = {
          name = "image-puller"
        }
      }

      spec {
        container {
          image = "gcr.io/google_containers/pause"
          name  = "pause"

        }

        init_container {
          image   = "docker"
          name    = "docker"
          command = ["/bin/sh", "-c"]
          args    = ["docker pull quay.io/prometheus/alertmanager:v0.20.0; docker pull squareup/ghostunnel:v1.5.2; docker pull jettech/kube-webhook-certgen:v1.0.0; docker pull quay.io/coreos/prometheus-operator:v0.36.0; docker pull quay.io/coreos/configmap-reload:v0.0.1; docker pull quay.io/coreos/prometheus-config-reloader:v0.36.0; docker pull k8s.gcr.io/hyperkube:v1.12.1; docker pull quay.io/prometheus/prometheus:v2.15.2;"]
          volume_mount {
            mount_path = "/var/run"
            name       = "docker"
          }

        }

        volume {
          host_path {
            path = "/var/run"
          }
          name = "docker"
        }
      }
    }
  }
}

resource "null_resource" "pulling_waiter" {
  depends_on = [
    kubernetes_daemonset.image_puller
  ]

  provisioner "local-exec" {
    command = <<EOT
      sleep 180
    
    EOT

  }
}

resource "helm_release" "prometheus_operator" {
  depends_on = [
    null_resource.pulling_waiter
  ]
  name       = "prometheus-operator"
  namespace  = "monitoring"
  repository = data.helm_repository.stable.metadata[0].name
  chart      = "prometheus-operator"

  values = [<<EOT
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          storageClassName: managed-premium-bind-wait
          resources:
            requests:
              storage: 5Gi

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          storageClassName: managed-premium-bind-wait
          resources:
            requests:
              storage: 5Gi

grafana:
  adminPassword: "${random_string.grafana_password.result}"
  persistence:
    enabled: true
    storageClassName: managed-premium-bind-wait
    accessModes: ["ReadWriteOnce"]
    size: 5Gi
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'sample'
        orgId: 1
        folder: 'sample'
        type: file
        disableDeletion: true
        editable: true
        options:
          path: /var/lib/grafana/dashboards/sample
  dashboards:
    sample:
      kubernetes-cluster:
        gnetId: 6417
        datasource: Prometheus

prometheus-node-exporter:
  service:
    port: 30206
    targetPort: 30206

kubeEtcd:
  enabled: false

kubeControllerManager:
  enabled: false

kubeScheduler:
  enabled: false
EOT
  ]
}

resource "helm_release" "kured" {
  name       = "kured"
  namespace  = "kube-system"
  repository = data.helm_repository.stable.metadata[0].name
  chart      = "kured"

  set {
    name  = "image.tag"
    value = "1.3.0"
  }

  set {
    name  = "extraArgs.time-zone"
    value = "Asia/Tokyo"
  }

  set {
    name  = "extraArgs.start-time"
    value = "09:00"
  }

  set {
    name  = "extraArgs.end-time"
    value = "17:00"
  }
}

