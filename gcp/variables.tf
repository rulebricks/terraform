variable "region" {
  description = "The GCP region to deploy to."
  default     = "us-central1"
}

variable "cluster_name" {
  description = "The name of the GKE cluster."
  default     = "rulebricks-cluster"
}

variable "node_group_name" {
  description = "The name of the node pool."
  default     = "rulebricks-node-group"
}

variable "machine_type" {
  description = "The machine type of the nodes."
  default     = "t2a-standard-4"  # ARM-based instance (Ampere Altra)
}

variable "initial_node_count" {
  description = "Desired number of worker nodes."
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of worker nodes."
  default     = 4
}

variable "min_node_count" {
  description = "Minimum number of worker nodes."
  default     = 1
}

variable "vpc_cidr" {
  description = "Custom VPC CIDR block. If not specified, defaults to 10.0.0.0/16"
  type        = string
  default     = ""
}

variable "project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "zone" {
  description = "The GCP zone for the cluster (optional, uses regional cluster if not specified)."
  type        = string
  default     = ""
}
