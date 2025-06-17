provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Create a virtual network for the AKS cluster
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.cluster_name}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    Environment = "Production"
    Terraform   = "true"
  }
}

# Create a subnet for the AKS cluster
resource "azurerm_subnet" "aks_subnet" {
  name                 = "${var.cluster_name}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "rulebricks"

  default_node_pool {
    name                = "default"
    vm_size             = var.vm_size
    vnet_subnet_id      = azurerm_subnet.aks_subnet.id
    enable_auto_scaling = var.enable_auto_scaling

    # Set node_count only when autoscaling is disabled
    node_count = var.enable_auto_scaling ? var.min_count : var.node_count

    # Set min/max only when autoscaling is enabled
    min_count = var.enable_auto_scaling ? var.min_count : null
    max_count = var.enable_auto_scaling ? var.max_count : null
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    dns_service_ip    = "10.0.2.10"
    service_cidr      = "10.0.2.0/24"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Production"
    Terraform   = "true"
  }
}
