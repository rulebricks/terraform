provider "google" {
  project = var.project_id
  region  = var.region
}

# Local values for consistent references
locals {
  vpc_cidr = var.vpc_cidr != "" ? var.vpc_cidr : "10.0.0.0/16"
}

# Create a VPC for the GKE cluster
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  description = "VPC for ${var.cluster_name} GKE cluster"

  lifecycle {
    ignore_changes = [description]
  }
}

# Create public subnet for load balancers
resource "google_compute_subnetwork" "public_subnet" {
  name          = "${var.cluster_name}-public-subnet"
  ip_cidr_range = cidrsubnet(local.vpc_cidr, 8, 1)
  region        = var.region
  network       = google_compute_network.vpc.id

  description = "Public subnet for load balancers"
}

# Create private subnet for GKE nodes
resource "google_compute_subnetwork" "private_subnet" {
  name          = "${var.cluster_name}-private-subnet"
  ip_cidr_range = cidrsubnet(local.vpc_cidr, 8, 101)
  region        = var.region
  network       = google_compute_network.vpc.id

  # Secondary ranges for pods and services
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = cidrsubnet(local.vpc_cidr, 4, 2)
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = cidrsubnet(local.vpc_cidr, 8, 201)
  }

  description = "Private subnet for GKE nodes"
}

# Firewall rule for Load Balancer (equivalent to AWS security group)
resource "google_compute_firewall" "load_balancer_fw" {
  name    = "${var.cluster_name}-lb-fw"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${var.cluster_name}-lb"]

  description = "Allow HTTP and HTTPS traffic to load balancers"
}

# Firewall rule for node communication
resource "google_compute_firewall" "node_group_fw" {
  name    = "${var.cluster_name}-node-fw"
  network = google_compute_network.vpc.name

  # Allow all internal communication
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_tags = ["${var.cluster_name}-node"]
  target_tags = ["${var.cluster_name}-node"]

  description = "Allow internal communication between nodes"
}

# Firewall rule to allow traffic from load balancer to nodes
resource "google_compute_firewall" "lb_to_nodes_fw" {
  name    = "${var.cluster_name}-lb-to-nodes-fw"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  source_tags = ["${var.cluster_name}-lb"]
  target_tags = ["${var.cluster_name}-node"]

  description = "Allow traffic from load balancers to nodes"
}

# Create GKE cluster
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone != "" ? var.zone : var.region

  # Remove default node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  min_master_version = "1.30"

  # Network configuration
  networking_mode = "VPC_NATIVE"
  network         = google_compute_network.vpc.name
  subnetwork      = google_compute_subnetwork.private_subnet.name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Master auth configuration
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Enable workload identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable logging and monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # Disable cluster autoscaling - we use node pool autoscaling instead
  cluster_autoscaling {
    enabled = false
  }

  # Security and maintenance settings
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = cidrsubnet(local.vpc_cidr, 12, 4094)
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All"
    }
  }

  resource_labels = {
    environment = "dev"
    terraform   = "true"
    name        = var.cluster_name
  }

  depends_on = [
    google_compute_network.vpc,
    google_compute_subnetwork.private_subnet
  ]
}

# Service account for nodes
resource "google_service_account" "nodes" {
  account_id   = "rb-cluster-nodes"
  display_name = "Service Account for ${var.cluster_name} nodes"
  project      = var.project_id

  lifecycle {
    ignore_changes = [display_name]
  }
}

# Grant necessary permissions to node service account
resource "google_project_iam_member" "nodes_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_project_iam_member" "nodes_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_project_iam_member" "nodes_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# Create node pool
resource "google_container_node_pool" "primary_nodes" {
  name     = var.node_group_name
  location = var.zone != "" ? var.zone : var.region
  cluster  = google_container_cluster.primary.name

  initial_node_count = var.initial_node_count

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = 50
    disk_type    = "pd-standard"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    service_account = google_service_account.nodes.email

    tags = ["${var.cluster_name}-node"]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      environment = "dev"
      terraform   = "true"
      cluster     = var.cluster_name
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  depends_on = [
    google_container_cluster.primary
  ]
}

# Service account for cluster autoscaler (workload identity)
resource "google_service_account" "cluster_autoscaler" {
  account_id   = "rb-cluster-autoscaler"
  display_name = "Cluster Autoscaler Service Account"
  project      = var.project_id

  lifecycle {
    ignore_changes = [display_name]
  }
}

# Grant necessary permissions for cluster autoscaler
resource "google_project_iam_member" "cluster_autoscaler_compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.cluster_autoscaler.email}"
}

resource "google_project_iam_member" "cluster_autoscaler_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.cluster_autoscaler.email}"
}

# Workload Identity binding for cluster autoscaler
resource "google_service_account_iam_binding" "cluster_autoscaler_workload_identity" {
  service_account_id = google_service_account.cluster_autoscaler.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[kube-system/cluster-autoscaler]"
  ]

  depends_on = [
    google_container_node_pool.primary_nodes
  ]
}

# Get GKE cluster credentials
data "google_client_config" "default" {}

data "google_container_cluster" "primary" {
  name     = google_container_cluster.primary.name
  location = google_container_cluster.primary.location
}

# Configure kubectl provider
provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

# Configure helm provider
provider "helm" {
  kubernetes {
    host                   = "https://${data.google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }
}

# Create storage class (GKE has built-in CSI drivers)
resource "kubernetes_storage_class" "pd_ssd" {
  metadata {
    name = "pd-ssd"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "kubernetes.io/gce-pd"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type = "pd-ssd"
  }

  depends_on = [google_container_node_pool.primary_nodes]
}

# Create Kubernetes service account for cluster autoscaler
resource "kubernetes_service_account" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.cluster_autoscaler.email
    }
  }

  depends_on = [google_container_node_pool.primary_nodes]
}

# Deploy Cluster Autoscaler using Helm
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.37.0"

  timeout = 600

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "cloudProvider"
    value = "gce"
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "false"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = kubernetes_service_account.cluster_autoscaler.metadata[0].name
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

  # Add ARM64 support
  set {
    name  = "nodeSelector.kubernetes\\.io/arch"
    value = "arm64"
  }

  set {
    name  = "tolerations[0].key"
    value = "kubernetes.io/arch"
  }

  set {
    name  = "tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "tolerations[0].value"
    value = "arm64"
  }

  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }

  depends_on = [
    google_container_node_pool.primary_nodes,
    kubernetes_service_account.cluster_autoscaler,
    google_service_account_iam_binding.cluster_autoscaler_workload_identity
  ]
}

# Create Cloud Router for NAT
resource "google_compute_router" "router" {
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id

  bgp {
    asn = 64514
  }
}

# Create NAT Gateway
resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
