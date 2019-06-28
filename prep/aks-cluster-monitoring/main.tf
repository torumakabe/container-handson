terraform {
  required_version = ">= 0.12"
}

provider "azurerm" {
  version = "~>1.30"
}

provider "azuread" {
  version = "~>0.4"
}

provider "random" {
  version = "~>2.0"
}

data "azurerm_subscription" "current" {}

resource "azurerm_log_analytics_workspace" "aks" {
  name                = "aks-la-workspace"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_resource_group" "aks" {
  name     = var.aks_cluster_rg
  location = var.aks_cluster_location
}

resource "azurerm_virtual_network" "vnet_default" {
  name                = "vnet-default"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  address_space       = ["10.0.0.0/8"]
}

resource "azurerm_subnet" "aks" {
  name                 = "subnet-aks"
  resource_group_name  = azurerm_resource_group.aks.name
  virtual_network_name = azurerm_virtual_network.vnet_default.name
  address_prefix       = "10.240.0.0/16"
}

resource "azuread_application" "aks" {
  name = "${var.aks_cluster_name}-aadapp"
  //  identifier_uris = ["https://${var.aks_cluster_name}-aadapp"]
}

resource "azuread_service_principal" "aks" {
  application_id = "${azuread_application.aks.application_id}"
}

resource "random_string" "aks_password" {
  length  = 32
  special = true
}

resource "azuread_service_principal_password" "aks" {
  end_date             = "2299-12-30T23:00:00Z" # Forever
  service_principal_id = azuread_service_principal.aks.id
  value                = random_string.aks_password.result
}

resource "azurerm_role_assignment" "aks" {
  depends_on           = ["azuread_service_principal_password.aks"]
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.aks.id

  // Waiting for AAD global replication
  provisioner "local-exec" {
    command = "sleep 60"
  }
}

resource "azurerm_kubernetes_cluster" "aks" {
  depends_on          = ["azurerm_role_assignment.aks"]
  name                = var.aks_cluster_name
  kubernetes_version  = "1.13.5"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = var.aks_cluster_name

  agent_pool_profile {
    name            = "pool1"
    type            = "VirtualMachineScaleSets"
    vnet_subnet_id  = azurerm_subnet.aks.id
    count           = 3
    vm_size         = "Standard_D2s_v3"
    os_type         = "Linux"
    os_disk_size_gb = 30
  }

  service_principal {
    client_id     = azuread_application.aks.application_id
    client_secret = random_string.aks_password.result
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
      log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
    }
  }

  provisioner "local-exec" {
    command = <<EOT
      az aks get-credentials -g ${azurerm_resource_group.aks.name} -n ${self.name} --admin --overwrite-existing;
    EOT
  }
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name = "aks-diag"
  target_resource_id = azurerm_kubernetes_cluster.aks.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id

  log {
    category = "kube-apiserver"
    enabled = true

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "kube-controller-manager"
    enabled = true

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "kube-scheduler"
    enabled = true

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "kube-audit"
    enabled = true

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "cluster-autoscaler"
    enabled = true

    retention_policy {
      enabled = false
    }
  }
}

resource "azurerm_monitor_action_group" "critical" {
  name = "critical"
  resource_group_name = azurerm_resource_group.aks.name
  short_name = "critical"

  email_receiver {
    name = "admin"
    email_address = var.admin_email_address
  }
}

resource "azurerm_monitor_metric_alert" "unhealthy_nodes" {
  name = "aks-unhealthy-nodes"
  resource_group_name = azurerm_resource_group.aks.name
  scopes = ["${azurerm_kubernetes_cluster.aks.id}"]
  frequency = "PT1M"
  window_size = "PT5M"
  severity = 3
  description = "Action will be triggered when not ready or unknown nodes count is greater than 0."

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name = "kube_node_status_condition"
    aggregation = "Total"
    operator = "GreaterThan"
    threshold = 0

    dimension {
      name = "status2"
      operator = "Include"
      values = ["NotReady", "Unknown"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }
}

resource "azurerm_application_insights" "sampleapp" {
  name = "aks-ai-sampleapp"
  location = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  application_type = "other"
}


/* Waiting for improvement in Terraform provider for Azure Monitor unified alert
resource "random_uuid" "webtest_id" {}
resource "random_uuid" "webtest_req_guid" {}

resource "azurerm_application_insights_web_test" "sampleapp" {
  name = "aks-ai-sampleapp-webtest"
  location = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  application_insights_id = "${azurerm_application_insights.sampleapp.id}"
  kind = "ping"
  frequency = 300
  timeout = 60
  enabled = true
  geo_locations = ["apac-jp-kaw-edge", "apac-hk-hkn-azr", "apac-sg-sin-azr"]

  configuration = <<XML
<WebTest  Name="WebTest"  Id="${random_uuid.webtest_id.result}"  Enabled="True"  CssProjectStructure=""  CssIteration="" Timeout="120" WorkItemIds=""  xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010" Description=""  CredentialUserName="" CredentialPassword="" PreAuthenticate="True"  Proxy="default" StopOnError="False" RecordedResultFile="" ResultsLocale="">
  <Items>
    <Request  Method="GET"  Guid="${random_uuid.webtest_req_guid.result}" Version="1.1" Url="http://${kubernetes_service.sampleapp_front.load_balancer_ingress.0.ip}" ThinkTime="0" Timeout="120" ParseDependentRequests="False"  FollowRedirects="True"  RecordResult="True" Cache="False" ResponseTimeGoal="0"  Encoding="utf-8"  ExpectedHttpStatusCode="200"  ExpectedResponseUrl=""  ReportingName=""  IgnoreHttpStatusCode="False" />
  </Items>
</WebTest>
XML
}
*/

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

resource "kubernetes_cluster_role" "log_reader" {
  metadata {
    name = "containerhealth-log-reader"
  }

  rule {
    api_groups = [""]
    resources = ["pods/log", "events"]
    verbs = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "log_reader" {
  metadata {
    name = "containerhealth-read-logs-global"
  }

  role_ref {
    kind = "ClusterRole"
    name = "containerhealth-log-reader"
    api_group = "rbac.authorization.k8s.io"
  }

  subject {
    kind = "User"
    name = "clusterUser"
    api_group = "rbac.authorization.k8s.io"
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

provider "helm" {
  version = "~>0.10"

  kubernetes {
    host                   = "${azurerm_kubernetes_cluster.aks.kube_config.0.host}"
    client_certificate     = "${base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)}"
    client_key             = "${base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)}"
    cluster_ca_certificate = "${base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)}"
  }

  install_tiller  = false
  namespace       = "kube-system"
  service_account = "tiller"
}

data "helm_repository" "default" {
  name = "default"
  url  = "https://kubernetes-charts-incubator.storage.googleapis.com/"
}

resource "random_string" "grafana_password" {
  length  = 32
  special = true
}

resource "helm_release" "prometheus_operator" {
  depends_on = ["null_resource.tiller_wait"]
  name       = "prometheus-operator"
  namespace  = "monitoring"
  repository = data.helm_repository.default.metadata[0].name
  chart      = "stable/prometheus-operator"
  timeout    = 1000

  values = [<<EOT
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          storageClassName: managed-premium
          resources:
            requests:
              storage: 5Gi

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          storageClassName: managed-premium
          resources:
            requests:
              storage: 5Gi

grafana:
  adminPassword: "${random_string.grafana_password.result}"
  persistence:
    enabled: true
    storageClassName: managed-premium
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

output "grafana_password" {
  value = random_string.grafana_password.result
}


resource "kubernetes_service" "sampleapp_front" {
  metadata {
    name = "front"
  }

  spec {
    selector = {
      app = "front"
    }

    port {
      port = 80
      target_port = 50030
    }

    type = "LoadBalancer"
  }
}

output "front_service_ip" {
  value = kubernetes_service.sampleapp_front.load_balancer_ingress.0.ip
}

resource "kubernetes_deployment" "sampleapp_front" {
  metadata {
    name = "front"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "front"
      }
    }

    template {
      metadata {
        labels = {
          app = "front"
        }
      }

      spec {
        container {
          image = "torumakabe/oc-go-app:1.0.0"
          name = "oc-go-app"

          port {
            container_port = 50030
          }

          env {
            name = "SERVICE_NAME"
            value = "front"
          }

          env {
            name = "OCAGENT_TRACE_EXPORTER_ENDPOINT"
            value = "localhost:55678"
          }

          env {
            name = "TARGET_SERVICE"
            value = "middle"
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 50030
            }

            initial_delay_seconds = 10
            period_seconds = 3
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 50030
            }

            initial_delay_seconds = 10
            period_seconds = 5
          }

        }

        container {
          image = "torumakabe/oc-local-forwarder:1.0.0"
          name = "oc-local-forwarder"

          port {
            container_port = 55678
          }

          env {
            name = "APPINSIGHTS_INSTRUMENTATIONKEY"
            value = azurerm_application_insights.sampleapp.instrumentation_key
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "sampleapp_middle" {
  metadata {
    name = "middle"
  }

  spec {
    selector = {
      app = "middle"
    }

    port {
      port = 80
      target_port = 50030
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "sampleapp_middle" {
  metadata {
    name = "middle"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "middle"
      }
    }

    template {
      metadata {
        labels = {
          app = "middle"
        }
      }

      spec {
        container {
          image = "torumakabe/oc-go-app:1.0.0"
          name = "oc-go-app"

          port {
            container_port = 50030
          }

          env {
            name = "SERVICE_NAME"
            value = "middle"
          }

          env {
            name = "OCAGENT_TRACE_EXPORTER_ENDPOINT"
            value = "localhost:55678"
          }

          env {
            name = "TARGET_SERVICE"
            value = "back"
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 50030
            }

            initial_delay_seconds = 10
            period_seconds = 3
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 50030
            }

            initial_delay_seconds = 10
            period_seconds = 5
          }

        }

        container {
          image = "torumakabe/oc-local-forwarder:1.0.0"
          name = "oc-local-forwarder"

          port {
            container_port = 55678
          }

          env {
            name = "APPINSIGHTS_INSTRUMENTATIONKEY"
            value = azurerm_application_insights.sampleapp.instrumentation_key
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "sampleapp_back" {
  metadata {
    name = "back"
  }

  spec {
    selector = {
      app = "back"
    }

    port {
      port = 80
      target_port = 50030
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "sampleapp_back" {
  metadata {
    name = "back"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "back"
      }
    }

    template {
      metadata {
        labels = {
          app = "back"
        }
      }

      spec {
        container {
          image = "torumakabe/oc-go-app:1.0.0"
          name = "oc-go-app"

          port {
            container_port = 50030
          }

          env {
            name = "SERVICE_NAME"
            value = "back"
          }

          env {
            name = "OCAGENT_TRACE_EXPORTER_ENDPOINT"
            value = "localhost:55678"
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 50030
            }

            initial_delay_seconds = 10
            period_seconds = 3
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 50030
            }

            initial_delay_seconds = 10
            period_seconds = 5
          }

        }

        container {
          image = "torumakabe/oc-local-forwarder:1.0.0"
          name = "oc-local-forwarder"

          port {
            container_port = 55678
          }

          env {
            name = "APPINSIGHTS_INSTRUMENTATIONKEY"
            value = azurerm_application_insights.sampleapp.instrumentation_key
          }
        }
      }
    }
  }
}

