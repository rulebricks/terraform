locals {
  kubeconfig = ""  # GKE requires gcloud CLI for authentication
}

output "cluster_security_group_id" {
  description = "ID of the GKE cluster security group (firewall rule)"
  value       = google_compute_firewall.node_group_fw.id
}

output "load_balancer_security_group_id" {
  description = "ID of the Load Balancer Security Group (firewall rule)"
  value       = google_compute_firewall.load_balancer_fw.id
}

output "node_security_group_id" {
  description = "ID of the GKE node security group (firewall rule)"
  value       = google_compute_firewall.node_group_fw.id
}

output "kubeconfig" {
  description = "Kubeconfig in YAML format"
  value       = local.kubeconfig
  sensitive   = true
}

output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  value = google_container_cluster.primary.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
}

output "region" {
  value = var.region
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --${var.zone != "" ? "zone ${var.zone}" : "region ${var.region}"} --project ${var.project_id}"
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = google_compute_network.vpc.id
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = [google_compute_subnetwork.public_subnet.id]
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = [google_compute_subnetwork.private_subnet.id]
}
