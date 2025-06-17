# Output the cluster name and kubeconfig
output "kube_config" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}

output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "vnet_id" {
  value = azurerm_virtual_network.vnet.id
}

output "subnet_id" {
  value = azurerm_subnet.aks_subnet.id
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}

output "location" {
  description = "The Azure region where resources are deployed"
  value       = azurerm_resource_group.rg.location
}

output "cluster_endpoint" {
  description = "The endpoint for the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.fqdn
}
