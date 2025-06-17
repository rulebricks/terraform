variable "project_id" {
  description = "The GCP project ID."
}

variable "region" {
  description = "The GCP region to deploy to."
  default     = "us-central1"
}

variable "cluster_name" {
  description = "The name of the GKE cluster."
  default     = "rulebricks-gke"
}

variable "initial_node_count" {
  description = "The initial number of nodes in the node pool."
  default     = 2
}

variable "machine_type" {
  description = "The machine type of the nodes."
  default     = "n2-standard-4"  # Default from CLI
}

variable "zone" {
  description = "The GCP zone for the cluster."
  default     = ""
}

variable "min_node_count" {
  description = "Minimum number of nodes for autoscaling."
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes for autoscaling."
  default     = 4
}

variable "enable_autoscaling" {
  description = "Enable autoscaling for the node pool."
  type        = bool
  default     = true
}
