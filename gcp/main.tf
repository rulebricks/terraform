provider "google" {
  project = var.project_id
  region  = var.region
}

# Create a VPC for the GKE cluster
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false

  # Use custom subnet mode for better control
  routing_mode = "REGIONAL"
}

# Create a subnet for the GKE cluster
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.0.0.0/20"
  region        = var.region
  network       = google_compute_network.vpc.id

  # Secondary ranges for pods and services
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/20"
  }
}

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone != "" ? var.zone : var.region

  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"
  network         = google_compute_network.vpc.name
  subnetwork      = google_compute_subnetwork.subnet.name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  resource_labels = {
    environment = "production"
    terraform   = "true"
    name        = var.cluster_name
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "primary-node-pool"
  location   = var.zone != "" ? var.zone : var.region
  cluster    = google_container_cluster.primary.name

  initial_node_count = var.initial_node_count

  autoscaling {
    min_node_count = var.enable_autoscaling ? var.min_node_count : var.initial_node_count
    max_node_count = var.enable_autoscaling ? var.max_node_count : var.initial_node_count
  }

  node_config {
    machine_type = var.machine_type

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    tags = ["gke-node", "${var.cluster_name}-node"]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      environment = "production"
      terraform   = "true"
      cluster     = var.cluster_name
    }
  }
}
