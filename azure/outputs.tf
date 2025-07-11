locals {
  kubeconfig = azurerm_kubernetes_cluster.aks.kube_config_raw
}

output "cluster_security_group_id" {
  description = "ID of the AKS cluster security group"
  value       = azurerm_network_security_group.node_group_nsg.id
}

output "load_balancer_security_group_id" {
  description = "ID of the Load Balancer Security Group"
  value       = azurerm_network_security_group.load_balancer_nsg.id
}

output "node_security_group_id" {
  description = "ID of the AKS node security group"
  value       = azurerm_network_security_group.node_group_nsg.id
}

output "kubeconfig" {
  description = "Kubeconfig in YAML format"
  value       = local.kubeconfig
  sensitive   = true
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "cluster_endpoint" {
  value = azurerm_kubernetes_cluster.aks.kube_config[0].host
  description = "Endpoint of the AKS cluster"
  sensitive = true
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "region" {
  value = var.location
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = azurerm_virtual_network.vnet.id
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = [azurerm_subnet.public_subnet.id]
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = [azurerm_subnet.private_subnet.id]
}
