variable "location" {
  description = "The Azure region to deploy to."
  default     = "East US"
}

variable "resource_group_name" {
  description = "The name of the resource group."
  default     = "rulebricks-rg"
}

variable "cluster_name" {
  description = "The name of the AKS cluster."
  default     = "rulebricks-aks"
}

variable "node_count" {
  description = "The initial number of nodes in the default node pool."
  default     = 2
}

variable "vm_size" {
  description = "The size of the VM instances."
  default     = "Standard_D4s_v5"  # ARM-based instance
}

variable "min_count" {
  description = "Minimum number of nodes for autoscaling."
  default     = 1
}

variable "max_count" {
  description = "Maximum number of nodes for autoscaling."
  default     = 4
}

variable "enable_auto_scaling" {
  description = "Enable autoscaling for the node pool."
  type        = bool
  default     = true
}
