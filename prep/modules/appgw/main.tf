provider "azurerm" {
  version = "~>1.39"
}

locals {
  backend_address_pool_name      = "ingress-beap"
  frontend_port_name             = "ingress-feport"
  frontend_ip_configuration_name = "ingress-feip"
  http_setting_name              = "ingress-be-htst"
  listener_name                  = "ingress-httplstn"
  request_routing_rule_name      = "ingress-rqrt"
}

resource "azurerm_subnet" "ingress_appgw" {
  name                 = "ingress_appgw_subnet"
  resource_group_name  = var.aks_cluster_rg
  virtual_network_name = var.vnet_default_name
  address_prefix       = "10.1.0.0/16"
}

resource "azurerm_public_ip" "ingress_appgw" {
  name                = "ingress-appgw-pip01"
  location            = var.aks_cluster_location
  resource_group_name = var.aks_cluster_rg
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "ingress" {
  //Workaround
  depends_on = [azurerm_subnet.ingress_appgw, azurerm_public_ip.ingress_appgw]

  name                = "ingress"
  resource_group_name = var.aks_cluster_rg
  location            = var.aks_cluster_location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "gateway-ipconf"
    subnet_id = azurerm_subnet.ingress_appgw.id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  frontend_port {
    name = "https-feport"
    port = 443
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.ingress_appgw.id
  }

  backend_address_pool {
    name = local.backend_address_pool_name
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 1
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }
}
