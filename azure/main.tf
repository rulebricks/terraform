provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Local values for consistent references
locals {
  vnet_cidr = var.vnet_cidr != "" ? var.vnet_cidr : "10.0.0.0/16"
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Create Network Security Group for Load Balancer
resource "azurerm_network_security_group" "load_balancer_nsg" {
  name                = "${var.cluster_name}-lb-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Name        = "${var.cluster_name}-lb-nsg"
    Environment = "dev"
    Terraform   = "true"
  }
}

# Create Network Security Group for AKS nodes
resource "azurerm_network_security_group" "node_group_nsg" {
  name                = "${var.cluster_name}-node-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = {
    Name        = "${var.cluster_name}-node-nsg"
    Environment = "dev"
    Terraform   = "true"
  }
}

# Create a virtual network for the AKS cluster
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.cluster_name}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [local.vnet_cidr]

  tags = {
    Environment = "dev"
    Name        = "${var.cluster_name}-vnet"
    Terraform   = "true"
  }
}

# Create public subnet for load balancer
resource "azurerm_subnet" "public_subnet" {
  name                 = "${var.cluster_name}-public-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [cidrsubnet(local.vnet_cidr, 8, 1)]
}

# Create private subnet for AKS nodes
resource "azurerm_subnet" "private_subnet" {
  name                 = "${var.cluster_name}-private-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [cidrsubnet(local.vnet_cidr, 8, 101)]
}

# Create Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "aks" {
  name                = "${var.cluster_name}-logs"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

# Create AKS cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = "1.30"

  default_node_pool {
    name                = "default"
    vm_size             = var.vm_size
    vnet_subnet_id      = azurerm_subnet.private_subnet.id
    auto_scaling_enabled = true
    min_count           = var.min_count
    max_count           = var.max_count
    os_disk_size_gb     = 50

    node_labels = {
      "Environment" = "dev"
      "Terraform"   = "true"
    }

    tags = {
      "Environment"                                   = "dev"
      "Terraform"                                     = "true"
      "k8s-cluster-autoscaler-enabled"                = "true"
      "k8s-cluster-autoscaler-${var.cluster_name}"    = "owned"
    }
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    dns_service_ip    = "10.2.0.10"
    service_cidr      = "10.2.0.0/24"
    load_balancer_sku = "standard"
  }

  identity {
    type = "SystemAssigned"
  }

  azure_policy_enabled             = true
  http_application_routing_enabled = false

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
  }

  # Auto-scaler profile
  auto_scaler_profile {
    scale_down_delay_after_add       = "5m"
    scale_down_unneeded              = "5m"
    scale_down_utilization_threshold = "0.5"
    expander                         = "least-waste"
    balance_similar_node_groups      = true
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

# Data source for AKS cluster credentials
data "azurerm_kubernetes_cluster" "aks" {
  name                = azurerm_kubernetes_cluster.aks.name
  resource_group_name = azurerm_resource_group.rg.name
  depends_on          = [azurerm_kubernetes_cluster.aks]
}

# Configure kubectl provider
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
}

# Configure helm provider
provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  }
}

# AKS automatically creates default storage classes, no need to create our own

# Deploy Cluster Autoscaler using Helm (although AKS has built-in autoscaling)
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.37.0"

  timeout = 600

  set {
    name  = "cloudProvider"
    value = "azure"
  }

  set {
    name  = "azureClientID"
    value = azurerm_kubernetes_cluster.aks.identity[0].principal_id
  }

  set {
    name  = "azureSubscriptionID"
    value = data.azurerm_subscription.current.subscription_id
  }

  set {
    name  = "azureTenantID"
    value = data.azurerm_subscription.current.tenant_id
  }

  set {
    name  = "azureResourceGroup"
    value = azurerm_kubernetes_cluster.aks.node_resource_group
  }

  set {
    name  = "azureVMType"
    value = "AKS"
  }

  set {
    name  = "azureClusterName"
    value = azurerm_kubernetes_cluster.aks.name
  }

  set {
    name  = "azureNodeResourceGroup"
    value = azurerm_kubernetes_cluster.aks.node_resource_group
  }

  # Set image for ARM compatibility
  set {
    name  = "image.tag"
    value = "v1.30.0"
  }

  set {
    name  = "image.repository"
    value = "registry.k8s.io/autoscaling/cluster-autoscaler"
  }

  # Cluster Autoscaler configuration
  set {
    name  = "extraArgs.scale-down-delay-after-add"
    value = "5m"
  }

  set {
    name  = "extraArgs.scale-down-unneeded-time"
    value = "5m"
  }

  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }

  set {
    name  = "extraArgs.expander"
    value = "least-waste"
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}

# Data source for current subscription
data "azurerm_subscription" "current" {}
