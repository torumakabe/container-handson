provider "azurerm" {
  version = "~>2.0"
  features {}
}

provider "azuread" {
  version = "~>0.7"
}

provider "random" {
  version = "~>2.1"
}

data "azurerm_subscription" "current" {}

data "azurerm_log_analytics_workspace" "aks" {
  name                = var.la_workspace_name
  resource_group_name = var.la_workspace_rg
}

resource "azuread_application" "aks" {
  name = "${var.aks_cluster_name}-aadapp"
  //  identifier_uris = ["https://${var.aks_cluster_name}-aadapp"]
}

resource "azuread_service_principal" "aks" {
  application_id = azuread_application.aks.application_id
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
  depends_on           = [azuread_service_principal_password.aks]
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.aks.id

  // Waiting for AAD global replication
  provisioner "local-exec" {
    command = "sleep 60"
  }
}

resource "azurerm_kubernetes_cluster" "aks" {
  depends_on          = [azurerm_role_assignment.aks]
  name                = var.aks_cluster_name
  kubernetes_version  = "1.16.4"
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
    /*    os_type             = "Linux" */
  }

  service_principal {
    client_id     = azuread_application.aks.application_id
    client_secret = random_string.password.result
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
  version = "~>1.0"

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

resource "helm_release" "prometheus_operator" {
  name       = "prometheus-operator"
  namespace  = "monitoring"
  repository = data.helm_repository.stable.metadata[0].name
  chart      = "stable/prometheus-operator"
  //  wait       = false

  values = [<<EOT
prometheusOperator:
  createCustomResource: false

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
  chart      = "stable/kured"
  //  wait       = false

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

