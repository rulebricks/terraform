# Move outputs from main.tf to this file for consistency

output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "region" {
  value = var.region
}

output "project_id" {
  value = var.project_id
}

output "vpc_id" {
  value = google_compute_network.vpc.id
}

output "subnet_id" {
  value = google_compute_subnetwork.subnet.id
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id}"
}

output "cluster_endpoint" {
  description = "The endpoint for the GKE cluster"
  value       = google_container_cluster.primary.endpoint
}

output "zone" {
  description = "The GCP zone where the cluster is deployed (if zonal)"
  value       = var.zone != "" ? var.zone : null
}

output "cluster_ca_certificate" {
  description = "Base64 encoded public certificate that is the root of trust for the cluster"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}
